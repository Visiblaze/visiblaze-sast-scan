#!/usr/bin/env bash
#
# Guard tests for the action wrapper.
#
# These run the REAL script out of action.yml rather than a copy of its logic, because a test that
# re-implements the guard it is testing passes whether or not the guard still exists.
#
# Scope, stated plainly. Covered here: the mode gate, the refusal to run unpinned, and a REAL
# tampered download rejected by the checksum guard - served over file:// with the pin overridden
# through ACTION_DIR, so it exercises the actual download path rather than a copy of it.
#
# NOT covered, and this file should not be read as covering them: a bad Opengrep signature, a
# missing OIDC token, a server-side tenant rejection, and "a dry run uploads nothing". Each needs a
# fake release and API endpoint that can also satisfy the steps before it - the signature check
# needs a genuine cosign, the OIDC cases need a token endpoint. They are exercised end to end on a
# private testbed today.
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
SKIPPED=0

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

# ── The checksum guard, exercised against a real tampered download ───────────────────────────
#
# The reviewer's first named case: "checksum mismatch -> abort". Everything above tests decisions
# the script makes before it touches the network; this one makes it actually fetch something and
# find that the bytes are not what the pin says.
#
# Served over file:// rather than from a local HTTP server, because curl supports it and a test
# that needs a background process is a test that hangs in someone's CI.
#
# The pin is overridden through ACTION_DIR, which is how the action locates pins.env - so this
# exercises the REAL download and verification path, not a copy of it.
checksum_case() {
  local name="$1" want_code="$2" mode="$3"
  local dir; dir="$(mktemp -d)"
  local artefact="${dir}/opengrep-artefact"

  printf 'this is not opengrep' > "$artefact"
  # A digest that is valid in form and wrong in fact. Using a malformed one would test the parser
  # rather than the comparison.
  cat > "${dir}/pins.env" <<PINS
SCANNER_BASE_URL=file://${dir}
OPENGREP_VERSION=v1.27.1
OPENGREP_URL_LINUX_AMD64=file://${artefact}
OPENGREP_SHA256_LINUX_AMD64=0000000000000000000000000000000000000000000000000000000000000000
OPENGREP_URL_LINUX_ARM64=file://${artefact}
OPENGREP_SHA256_LINUX_ARM64=0000000000000000000000000000000000000000000000000000000000000000
SCANNER_VERSION=v0.0.0-test
SCANNER_SHA256_LINUX_AMD64=1111111111111111111111111111111111111111111111111111111111111111
SCANNER_SHA256_LINUX_ARM64=1111111111111111111111111111111111111111111111111111111111111111
COSIGN_VERSION=v3.1.3
COSIGN_URL_LINUX_AMD64=file://${artefact}
COSIGN_SHA256_LINUX_AMD64=2222222222222222222222222222222222222222222222222222222222222222
COSIGN_URL_LINUX_ARM64=file://${artefact}
COSIGN_SHA256_LINUX_ARM64=2222222222222222222222222222222222222222222222222222222222222222
OPENGREP_CERT_IDENTITY=https://example.invalid/wf.yml@refs/heads/main
OPENGREP_CERT_OIDC_ISSUER=https://token.actions.githubusercontent.com
ALLOWED_API_ORIGINS=https://example.invalid
PINS

  local out code
  out="$(env IN_MODE="$mode" FAIL_ON_ERROR=false ACTION_DIR="$dir" \
           GITHUB_WORKSPACE="$dir" GITHUB_OUTPUT="$(mktemp)" \
           bash "$SCRIPT" 2>&1)"
  code=$?
  rm -rf "$dir"

  if [ "$code" = "$want_code" ] && printf '%s' "$out" | grep -qF "checksum mismatch"; then
    echo "  ok    $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $name"
    echo "        want exit $want_code and a checksum mismatch"
    echo "        got  exit $code: $(printf '%s' "$out" | tail -2 | head -1)"
    FAIL=$((FAIL + 1))
  fi
}

# The bytes do not match the pin, so nothing is executed. Reported in advisory mode, fatal in gate.
#
# Linux only, because the action refuses to run anywhere else and bails before it downloads
# anything. Counted as SKIPPED rather than passed: a case that did not execute must not read as one
# that did - which is exactly how the rule fixtures in the platform repo went green for a week
# while asserting nothing.
if [ "$(uname -s)" = "Linux" ]; then
  checksum_case "checksum mismatch aborts (advisory reports)" 0 advisory
  checksum_case "checksum mismatch aborts (gate fails)"       1 gate
else
  echo "  SKIP  checksum mismatch (needs Linux; the action refuses to run on $(uname -s))"
  echo "  SKIP  checksum mismatch in gate mode (same reason)"
  SKIPPED=2
fi

# ── The flag probes must not lose a race with their own producer ───────────────
#
# Extracted from the real action.yml, so it tests the shipped probe rather than a copy. The bug it
# guards: `cmd --help | grep -q FLAG` under `set -o pipefail` fails whenever grep exits on the match
# before the producer finishes writing — the producer takes SIGPIPE and pipefail reports the whole
# pipeline as failed even though grep matched. MEASURED with the real scanner under bash 5.3 + BSD
# grep: 7 detections in 200. On GNU grep it happened to work, which is what made it dangerous.
#
# 40 iterations, and the assertion is 40/40 rather than "most": an intermittent probe silently
# skips the entire baseline block and the check then reports "no baseline, nothing was compared".
probe_stub="$(mktemp -d)/visiblaze-scan"
cat > "$probe_stub" <<'STUB'
#!/usr/bin/env bash
echo "Usage of visiblaze-scan:"
echo "  -base-dir string"
echo "  -base-sha string"
# Keep writing well past the match, and past the 64K pipe buffer, which is what opens the window.
awk 'BEGIN{for(i=0;i<4000;i++) printf "  -flag%d string  padding\n", i}'
STUB
chmod +x "$probe_stub"

probe_hits() {   # $1 = flag to look for; echoes how many of 40 runs detected it
  local flag="$1" n=0 i
  for i in $(seq 1 40); do
    (
      set -uo pipefail
      HELP_OUT="$("$probe_stub" --help 2>&1 || true)"
      case "$HELP_OUT" in *"$flag"*) exit 0 ;; *) exit 1 ;; esac
    ) && n=$((n + 1))
  done
  echo "$n"
}

for flag in -base-dir -base-sha; do
  got="$(probe_hits "$flag")"
  if [ "$got" = "40" ]; then
    echo "  ok    the ${flag} probe detects it on every run, with a producer that outlives the match"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  the ${flag} probe is racy: detected ${got}/40"
    echo "        a missed detection skips the baseline silently — the check then reports nothing was compared"
    FAIL=$((FAIL + 1))
  fi
done

# And assert the shipped file does not reuse the broken form for either probe.
if grep -nE '\| *grep -q --? "?-base-(dir|sha)' "$ACTION" >/dev/null 2>&1; then
  echo "  FAIL  action.yml pipes a flag probe into grep -q again; capture into HELP_OUT and use case"
  FAIL=$((FAIL + 1))
else
  echo "  ok    neither flag probe pipes into grep -q"
  PASS=$((PASS + 1))
fi

echo
if [ "$FAIL" -gt 0 ]; then
  echo "$PASS passed, $FAIL failed, ${SKIPPED:-0} skipped"
  exit 1
fi
if [ "${SKIPPED:-0}" -gt 0 ]; then
  echo "$PASS passed, $SKIPPED skipped (run on Linux, or in a container, for full coverage)"
else
  echo "$PASS passed"
fi
