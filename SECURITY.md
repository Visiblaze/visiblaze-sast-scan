# Security policy

## Why this repository warrants a policy of its own

The action in this repository runs inside **your** CI job, reads **your** source code, and holds
a GitHub OIDC token minted with `id-token: write`. Code in that position deserves to be read
before it is trusted, which is why this repository is public and Apache-2.0 licensed rather than
a prebuilt binary you are asked to take on faith.

Three design decisions follow from that, and all three are load-bearing:

- **Your source code never leaves your runner.** The scanner analyses your checkout in place and
  transmits *locations* — file path, line, rule id, a fingerprint — never source text. A finding
  says `api/search.py:87`, not what line 87 contains. This is the property the whole design rests
  on, and it is why a finding cannot be used to reconstruct your code.
- **No long-lived secret is stored in your CI.** Authentication is a short-lived GitHub-signed
  OIDC token, verified server-side against GitHub's published keys, and minted at the moment
  results are posted rather than at startup — so a long scan cannot outlive its own credential.
  There is no API key to leak, rotate, or exfiltrate from your runner.
- **Every downloaded binary is pinned and checksummed.** The action fetches a third-party
  scanning engine at job time. Its version, URL and SHA-256 are pinned in `pins.env`, verified
  before execution, and the action **refuses to run** rather than execute an unpinned or
  mismatched artefact. We are asking you to run code we did not write; verifying it is our job,
  not yours.

## Third-party components

This action downloads and executes a third-party static-analysis engine inside your job. Its
licence, version and checksums are recorded in `pins.env` and its attribution in `NOTICE`.
Nothing in this repository modifies or links against it — it is invoked as a separate process.

## Reporting a vulnerability

Please report privately, not in a public issue.

Use **[GitHub private vulnerability reporting](https://github.com/Visiblaze/visiblaze-sast-scan/security/advisories/new)**
on this repository. If that is unavailable to you, email **security@visiblaze.com**.

Please include enough to reproduce: the action version or commit SHA you ran, the runner OS and
architecture, and a **minimal synthetic repository** that triggers it. **Do not send us your real
source code, real findings, or real credentials** — a synthetic reproduction is more useful and
safer for both of us.

### What to expect

| | |
|---|---|
| Acknowledgement | within 3 business days |
| Initial assessment | within 10 business days |
| Fix or mitigation plan | communicated with the assessment |

If a report affects the scanning engine rather than this action, we will say so and point you at
the upstream project — we will not sit on it silently.

## Scope

In scope: this action, its release artefacts, the pinning and verification mechanism, and
anything that could cause your source, credentials or OIDC token to leave your runner.

Out of scope: findings you disagree with. A false positive or a missed vulnerability is a
correctness issue, not a security one — please open a normal issue for those.
