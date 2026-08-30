# Security policy

## Why this repository warrants a policy of its own

This action reads **your entire source tree** on your own runner, beside your credentials, and
then sends Visiblaze a description of what it found. Two properties matter more than anything
else in this repository, and both are things you should be able to check rather than take on
trust:

- **Your source code never leaves your runner.** Opengrep reads it locally. What is transmitted
  is finding metadata — rule id, severity, file path, line numbers, CWE, a fingerprint. Not file
  contents, not matched lines, not code snippets, not raw scanner output.
- **A failed scan is never reported as a clean one.** A run that was cut short reports itself as
  partial, and a partial run is never allowed to mark anything as resolved.

A defect in either of those is the most serious thing that can go wrong here, and we would rather
hear about it from you than from a customer.

## Reporting a vulnerability

Please report privately, not in a public issue.

Use **[GitHub private vulnerability reporting](https://github.com/Visiblaze/visiblaze-sast-scan/security/advisories/new)**
on this repository. If that is unavailable to you, email **security@visiblaze.com**.

Please include enough to reproduce: the commit SHA of the action you ran, the versions reported
in the job log (`opengrep` and `visiblaze-scan`), and a **minimal synthetic** repository that
triggers it. **Do not send us your real source, real findings, or real credentials** — a small
made-up reproduction is more useful and safer for both of us.

### What to expect

| | |
|---|---|
| Acknowledgement | within 3 business days |
| Initial assessment | within 10 business days |
| Fix or mitigation plan | communicated with the assessment |

We will tell you what we conclude, including when we conclude a report is not a vulnerability and
why. If you would like credit in the advisory, say so and give us the name to use.

## Scope

**In scope** — anything in this repository, and anything the action downloads and executes:

- **Source-code leakage.** Any path by which file contents, matched lines, code snippets, or raw
  Opengrep output could reach Visiblaze. This is the highest-severity class here.
- **Unexpected fields leaving the runner.** The wire format is a closed schema; a field the schema
  does not declare should be undecodable rather than merely unused. A way to smuggle one out is a
  vulnerability even if the field looks harmless.
- **Token leakage.** Anything causing the GitHub OIDC token, or any other credential present in
  the job, to be logged, written to a file, or transmitted anywhere other than the Visiblaze
  ingest endpoint it was minted for.
- **Incorrect OIDC handling.** In particular, a token minted for one Visiblaze audience being
  accepted at an endpoint expecting another.
- **Command injection through action inputs**, or through repository-controlled data — file names,
  branch names, rule names, or scanner output becoming executable shell syntax.
- **Checksum or signature verification bypass.** Anything that lets an unpinned, unverified, or
  substituted binary execute.
- **Scanner supply-chain compromise** in how this action fetches, verifies and runs its
  dependencies.
- **Malicious rule execution** — a rule causing anything beyond static analysis to happen.
- **Path traversal**, including writing outside the temporary working directory.
- **A failed or truncated scan being reported as successful or complete.**
- **Findings attributed to the wrong tenant or repository.**

**Out of scope here** — but still wanted, via the same channels:

- **The Visiblaze platform and its APIs.** Those are covered by your commercial agreement, not by
  this licence, and are not part of this repository.
- **Vulnerabilities inside Opengrep itself**, unless this action's use of it materially worsens
  the issue. Report those to [opengrep/opengrep](https://github.com/opengrep/opengrep) and tell us
  if our integration makes it worse.
- **Vulnerabilities in GitHub Actions itself.**
- Findings that require an attacker to **already control the runner**. If they run the job, they
  already have your source and your tokens; this action is not the weak link in that scenario.

## What this action downloads

Everything executed is pinned by exact version and verified before it runs. The pins live in
[`pins.env`](pins.env) and are readable in the same commit you pin.

| Component | Verified by |
|---|---|
| Opengrep | SHA-256 digest, plus cosign signature verification |
| cosign | SHA-256 digest |
| `visiblaze-scan` | SHA-256 digest from the release's `checksums.txt` |

If a digest does not match, the action **fails and executes nothing**. There is no fallback to an
unpinned or "latest" build.

**One limitation stated plainly:** `visiblaze-scan` is a compiled binary. You can verify *what*
you are running by digest, but you cannot read its source in this repository the way you can read
`action.yml`. If that matters for your review, contact us — we would rather have the conversation
than have you assume.

## Supported versions

Pin to a **commit SHA**, not a tag or branch:

```yaml
- uses: Visiblaze/visiblaze-sast-scan@<full-40-char-sha>
```

A tag is a movable pointer. Pinning a SHA means the code that runs beside your source and your
credentials cannot change without you changing it. Only the latest commit on `main` receives
fixes; there are no maintained release branches.
