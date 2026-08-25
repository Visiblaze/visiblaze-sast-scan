# Visiblaze SAST

Scan your source for vulnerabilities on your own runner. Only the findings are sent to Visiblaze —
your code never leaves your network.

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

Pin a **commit SHA**, not a tag. A tag can be moved to point at different code; a SHA cannot.

`api-url` is region-specific — your Visiblaze admin is given the exact endpoint when your
organisation is authorised. The placeholder above is not a working URL.

## What leaves your network

| Sent | Not sent |
|---|---|
| Rule id, severity, confidence | Your source code |
| File path and line numbers | File contents |
| CWE / OWASP references | Your dependencies or lockfiles |
| Source-to-sink data flow, as file+line steps within one file | Your secrets, environment, or credentials |

The action reads. It does not write, comment, annotate, or open pull requests. The only effect it
can have on your pipeline is an exit code, and only if you ask for one with `fail-on`.

## There is no secret to configure

Authentication is GitHub's own OIDC. Your job mints a short-lived token that GitHub signs and that
states cryptographically which repository produced it. Nothing is stored in your repository
secrets, so there is nothing to rotate, leak, or revoke — and a token captured from a log cannot be
replayed against another tenant.

`permissions: id-token: write` is what allows that minting. Without it GitHub sets no token
endpoint and the action fails with that instruction rather than a confusing 401.

Your Visiblaze admin authorises your organisation or repository once. **Until they do, the first
run gets a 403 and says so** — that is the expected first-run experience, and it is also what puts
your request in front of your admin.

## Monorepos: one job per package

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

## Blocking a pull request

`fail-on` exits 2 when a finding at or above that severity is present. Findings are reported either
way; this only decides whether the job goes red.

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

## First run

Start with `dry-run: true`. It scans and prints the exact payload without sending anything, so you
can read what would leave before it does.

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

## Licence

Apache-2.0. See [LICENSE](LICENSE).
