# Visiblaze SAST

Scan source code on your own CI runner. Only findings are sent to Visiblaze — **your code never
leaves your environment.**

- **Runs in your environment.** Opengrep reads your source on your runner. We receive locations, not code.
- **No long-lived CI secrets.** Authentication is short-lived GitHub OIDC. There is nothing to store, rotate, or leak.
- **Findings join the bigger picture.** Code findings sit alongside cloud, device, posture and runtime context in Visiblaze, so what gets prioritised reflects more than one signal.

## Quick start

```yaml
name: Security
on:
  push:
    branches: [main]

jobs:
  sast:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write        # required — this is how the action authenticates
    steps:
      - uses: actions/checkout@v4
      - uses: Visiblaze/visiblaze-sast-scan@<commit-sha>
        with:
          tenant: your-tenant-id
          api-url: https://<your-visiblaze-ingest-endpoint>/v1/code/findings
```

Pin a **commit SHA**, not a tag. A tag can be moved to point at different code; a SHA cannot. The
same property means a scanner update reaches you when you re-pin — not before.

`api-url` is region-specific — your Visiblaze admin is given the exact endpoint when your
organisation is authorised. The placeholder above is not a working URL.

### Recommended first run

Add `dry-run: true`. It scans and prints the exact payload without uploading anything, so you can
read what would leave your environment before any of it does.

It analyses with the same rules a reporting run would, which means it makes **one** request to
Visiblaze: an unauthenticated `GET` for the current rule pack. That is the only request a dry run
makes to us, it carries no credential, and it sends nothing about your code — but it is a request,
and a preview that used different rules from the real run would not be worth reading.

Leave `api-url` out entirely and the dry run contacts us not at all. It then analyses with the
rules built into the scanner, and says so.

```yaml
        with:
          tenant: your-tenant-id
          api-url: https://<your-visiblaze-ingest-endpoint>/v1/code/findings
          dry-run: true
```

### Before your first upload

Your Visiblaze administrator authorises the GitHub organisation or repository once. **Until that is
done, uploads are rejected with a 403 and the action says so.** That is the expected first-run
experience rather than a broken setup — the rejected request is also what puts your authorisation
request in front of your admin.

## How it works

```
your GitHub runner  ──►  Visiblaze SAST action  ──►  Opengrep scans your source, locally
                                                              │
                                          findings only ──────┘
                                                │
                                                ▼
                                            Visiblaze
```

The source is read on your runner and stays there. What crosses the boundary is finding metadata.

Every binary the action executes is version-pinned and SHA-256 verified before it runs — details in
[Every binary is pinned and verified](#every-binary-is-pinned-and-verified).

## What leaves your network

| Sent | Not sent |
|---|---|
| Rule id, severity, confidence | Your source code |
| File path and line numbers | File contents |
| CWE / OWASP references | Your dependencies or lockfiles |
| Source-to-sink data flow, as file+line steps within one file | Your secrets, environment, or credentials |

The action reads. It does not write, comment, annotate, or open pull requests. The only effect it
can have on your pipeline is an exit code.

On a pull request it also analyses your merge base, to tell findings this change introduced from
findings the branch already had. **That second analysis is uploaded nowhere.** It exists only to be
compared against, inside the same process, on your runner — the results sent to Visiblaze are your
head commit's, exactly as on a push.

## There is no secret to configure

Authentication is GitHub's own OIDC. Your job mints a short-lived token that GitHub signs and that
states cryptographically which repository produced it. Nothing is stored in your repository
secrets, so there is nothing to rotate, leak, or revoke.

The token is verified against GitHub's published keys, with the issuer and the audience both pinned
and an expiry required. Your tenant is resolved from the authorised binding for the repository that
minted the token — never from the request — so a token captured from a log cannot be used to write
into a different tenant.

`permissions: id-token: write` is what allows that minting. Without it GitHub sets no token
endpoint and the action fails with that instruction rather than a confusing 401.

## Blocking a pull request

Two separate things can fail a build, they are not interchangeable, and it is worth knowing which
one stopped you.

### `fail-on` — your own, and it counts everything

`fail-on` exits 2 when a finding at or above that severity is present **anywhere in what was
scanned**, whether this change introduced it or not. That is a defensible setting for a team that
wants "no criticals ever, including the ones already there", and it is the wrong setting if you
expected only new problems to block. Findings are reported either way; this decides only whether the
job goes red.

```yaml
        with:
          tenant: your-tenant-id
          api-url: https://<your-visiblaze-ingest-endpoint>/v1/code/findings
          fail-on: high
```

Exit codes are deliberately distinct: **2** means your code has a problem you asked to block on,
**1** means the tool had a problem. A check that cannot tell those apart is one people learn to
ignore.

`fail-on-error` (default `false`) controls the second case. The default is deliberate — a scanner
outage should not be the reason your deploy pipeline goes red.

### Your organisation's policy — new findings only

Your Visiblaze administrator can set a threshold centrally, and that one blocks on findings **this
change introduced** and never on findings the branch already had. You configure nothing here; the
action asks for the policy as part of the upload it already makes.

To tell new from inherited, the action scans the merge base as well as your head commit — on a
pull request, automatically. Nothing is compared on a push, because a push has no proposed change to
be new relative to.

It costs one extra analysis pass. Not one extra job: the runner, the binaries and their verification
are already paid for, so on a small repository this is around **+15%** of job time and on one of
~1,500 files around **+70%**. If you split a monorepo across jobs with `path`, each job scans and
compares only its own subtree.

Everything about that comparison degrades toward **not blocking**. A shallow checkout we cannot
deepen, a merge base git cannot resolve, a subtree that did not exist on the base, a baseline scan
that fails or comes back partial — each of them means no finding can be shown to be new, so none of
them blocks, and the run says which happened. A repository we cannot build a baseline for does not
get failing builds because of that.

The two mechanisms do not interact. `fail-on` is yours and lives in this file; the policy is your
organisation's and lives in Visiblaze. Either can fail a build, and the message names which did.

## Inputs

| Input | Required | Default | Notes |
|---|---|---|---|
| `tenant` | yes | — | Findings posted against the wrong tenant are not fixed by re-running |
| `api-url` | yes | — | Region-specific; you get the exact URL when your org is authorised |
| `repo-key` | no | this repo's numeric id | Only set it if you know you need to; the server rejects mismatches |
| `path` | no | `.` | Directory to scan; also becomes the declared coverage |
| `scope` | no | derived from `path` | Comma-separated; for multi-directory jobs only |
| `fail-on` | no | *(empty)* | `critical` \| `high` \| `medium` \| `low` |
| `fail-on-error` | no | `false` | Fail the job if the scan or upload itself fails |
| `dry-run` | no | `false` | Scan and print what would be sent; upload nothing |

**Outputs:** `findings` (count), `status` (`sent` \| `dry-run` \| `failed`), `policy`
(`pass` \| `fail` \| `not-applied`).

## What the analysis can and cannot find

The engine follows tainted input **within a single file**. A flow that crosses files — user input
received in one module, reaching a dangerous call in another — is not reported. That is a real
ceiling and it is stated here rather than discovered later: a clean result means "nothing found by
the checks we run", not "this code is safe".

## Every binary is pinned and verified

The action downloads two executables onto your runner: the Visiblaze scanner and the Opengrep
analysis engine. Both are pinned to exact versions in [`pins.env`](pins.env), and both have their
SHA-256 verified **before** execution — a mismatch aborts and runs nothing.

There is no `latest` anywhere. A floating dependency inside a pinned action would mean the SHA you
pinned does not actually determine what runs on your machine.

The action is a composite shell script, not a Docker image, so you can read exactly what it does
before you run it.

## Advanced: monorepos, one job per package

A repository may be scanned by several jobs. Each job **declares what it covered**, so they do not
resolve each other's findings — without that, each job would report "complete", the platform would
resolve everything that job did not see, and the repository would flicker between whichever job ran
last.

`path` does this for you: point a job at a directory and that directory becomes its declared
coverage.

```yaml
jobs:
  sast:
    strategy:
      matrix:
        package: [packages/api, packages/web, packages/worker]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: Visiblaze/visiblaze-sast-scan@<commit-sha>
        with:
          tenant: your-tenant-id
          api-url: https://<your-visiblaze-ingest-endpoint>/v1/code/findings
          path: ${{ matrix.package }}
```

Use `scope` only when one job scans several non-adjacent directories:

```yaml
          path: .
          scope: packages/api,packages/worker,libs/shared
```

A scope **narrower** than what you actually scanned is worse than none: findings you fixed outside
it are never marked resolved. Leaving it to `path` avoids that.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
