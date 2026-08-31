#!/usr/bin/env bash
#
# Guard tests for the action wrapper.
#
# These run the REAL script out of action.yml rather than a copy of its logic, because a test that
# re-implements the guard it is testing passes whether or not the guard still exists.
#
# Scope, stated plainly: this covers the guards that fire before anything is downloaded. The rest -
# checksum mismatch, bad Opengrep signature, missing OIDC, upload rejection - need a harness that
# stands up fake release and API endpoints, which is not built. Those are exercised end to end on a
# private testbed today; they are not covered here, and this file should not be read as covering
# them.
#
# Usage: tests/guards.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ACTION="${HERE}/../action.yml"
SCRIPT="$(mktemp)"
trap 'rm -f "$SCRIPT"' EXIT

python3 - "$ACTION" "$SCRIPT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
open(sys.argv[2], "w").write("#!/usr/bin/env bash\n" + d["runs"]["steps"][0]["run"])
PY
chmod +x "$SCRIPT"

PASS=0
FAIL=0

# Runs the wrapper with a throwaway GITHUB_OUTPUT and the given environment, and checks the exit
# status and that the message names the actual problem.
expect() {
  local name="$1" want_code="$2" want_text="$3"; shift 3
  local out code
  out="$(env "$@" GITHUB_OUTPUT="$(mktemp)" bash "$SCRIPT" 2>&1)"
  code=$?
  if [ "$code" = "$want_code" ] && printf '%s' "$out" | grep -qF "$want_text"; then
    echo "  ok    $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $name"
    echo "        want exit $want_code containing: $want_text"
    echo "        got  exit $code: $(printf '%s' "$out" | head -3)"
    FAIL=$((FAIL + 1))
  fi
}

echo "action guards"

# A misspelled mode must not quietly become advisory. Someone writing `mode: gate` is trying to
# make the check able to fail; silently giving them one that cannot is the worst outcome.
expect "unknown mode is refused" 1 "mode must be 'advisory' or 'gate'" \
  IN_MODE=blocking FAIL_ON_ERROR=false

expect "mode is case sensitive" 1 "mode must be 'advisory' or 'gate'" \
  IN_MODE=Gate FAIL_ON_ERROR=false

# Advisory is the default and must stay non-failing: a scanner outage is not a reason to redden a
# deploy pipeline for someone who has not opted into gating.
expect "advisory does not fail the job" 0 "pins.env is missing" \
  IN_MODE=advisory FAIL_ON_ERROR=false ACTION_DIR=/nonexistent

# Gate mode is the whole point of the input: the same broken run now fails.
expect "gate fails the job" 1 "pins.env is missing" \
  IN_MODE=gate FAIL_ON_ERROR=false ACTION_DIR=/nonexistent

# fail-on-error predates mode and must keep working on its own, or upgrading the action silently
# removes a guarantee an existing workflow asked for.
expect "fail-on-error still fails closed" 1 "pins.env is missing" \
  IN_MODE=advisory FAIL_ON_ERROR=true ACTION_DIR=/nonexistent

echo
if [ "$FAIL" -gt 0 ]; then
  echo "$PASS passed, $FAIL failed"
  exit 1
fi
echo "$PASS passed"
