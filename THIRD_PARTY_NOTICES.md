# Third-party notices

This action is Apache-2.0. It does not redistribute the components below: it downloads each at run
time, at the version and digest pinned in [`pins.env`](pins.env), onto the runner executing the
workflow. They are listed here because a security or procurement review should not have to read a
shell script to find out what ends up on the machine.

## Downloaded at run time

### Opengrep

- **Version** 1.27.1 (pinned)
- **Licence** LGPL-2.1
- **Source** https://github.com/opengrep/opengrep
- **Role** the static-analysis engine. Runs entirely on your runner and reads your source; nothing
  it reads leaves the machine.
- **Verified by** SHA-256 committed in `pins.env`, plus a Sigstore signature check against the
  upstream release workflow identity.

### Sigstore Cosign

- **Version** 3.1.3 (pinned)
- **Licence** Apache-2.0
- **Source** https://github.com/sigstore/cosign
- **Role** verifies the Opengrep signature. Contacts `rekor.sigstore.dev` to do so — the one
  outbound request this action makes that is not to Visiblaze.
- **Verified by** SHA-256 committed in `pins.env`.

### Visiblaze scanner (`visiblaze-scan`)

- **Version** see `SCANNER_VERSION` in `pins.env`
- **Licence** proprietary, © Visiblaze
- **Source** not public. Distributed as a released binary from this repository.
- **Role** invokes Opengrep with the Visiblaze rule pack, normalises results, and uploads finding
  metadata. Source code is never uploaded.
- **Verified by** SHA-256 committed in `pins.env`. The digest lives in this repository rather than
  in the release, so the action SHA you pin determines the bytes that run.

## Also used, already present on GitHub-hosted runners

`bash`, `curl`, `tar`, `awk`, `git`, and `sha256sum` (or `shasum` on macOS runners). The action
does not install these.

## Rules

The rule pack this scanner runs is authored by Visiblaze. It does not incorporate rules from
corpora under the Semgrep Rules License or a Commons Clause, both of which restrict commercial
redistribution — which is why the pack is written from scratch rather than adapted.

Per-rule provenance metadata (origin, licence, upstream commit where applicable) is not yet
recorded in the pack. It is tracked and not yet built; this note exists so the absence is stated
rather than assumed either way.
