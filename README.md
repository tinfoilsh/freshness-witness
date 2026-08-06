# Tinfoil freshness witness

Publishes a small, independently-signed **freshness witness** per tracked
repo, re-checked on a schedule and on demand, so verifiers can bound how
long a Sigstore-published Tinfoil artifact can be trusted without an active
re-endorsement — without needing a revocation mechanism.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

Status: **pilot**, tracking `tinfoilsh/platform-endorsements` only.

## How it works

For each tracked repo (`repos.json`), the workflow:

1. Resolves the repo's current release tag and commit, downloads its artifact,
   and checks the published `tinfoil.hash`.
2. Independently verifies the artifact's existing Sigstore attestation against
   the configured predicate and workflow identity.
3. Publishes an [`actions/attest`](https://github.com/actions/attest)
   attestation against the verified source attestation's same subject name and
   digest. No witness file is hosted in this repo.

A verifier holding a digest for `tinfoilsh/platform-endorsements` (or any
other tracked repo) looks up its freshness witness with one call to GitHub's
Artifact Attestations API, keyed by that same digest:

```
GET https://api.github.com/repos/tinfoilsh/freshness-witness/attestations/sha256:<digest>
```

If a recent witness exists (`issued_at` within the verifier's hardcoded
`MaxFreshnessAge`, e.g. 7 days) and it's signed by this repo's expected
workflow identity, the artifact at that digest is considered fresh.

## Witness shape

```json
{
  "format": "https://tinfoil.sh/predicate/freshness-witness/v1",
  "endorses": {
    "repo": "tinfoilsh/platform-endorsements",
    "tag": "v0.0.4",
    "commit": "<40-character Git commit>",
    "subject": {
      "name": "platform-endorsements.json",
      "digest": "sha256:<hex>"
    }
  }
}
```

There are deliberately no publisher-controlled time fields. Verifiers use the
earliest authenticated RFC 3161 timestamp from GitHub's Sigstore bundle and
enforce a hardcoded seven-day maximum age.

## Triggers

- **Scheduled**: dispatched externally by Tinfoil's control plane on a
  cadence tighter than the verifier-side `MaxFreshnessAge` (e.g. every 5–6
  days), re-signing every tracked repo unconditionally — this is the
  heartbeat that keeps witnesses from aging out.
- **Event-driven**: a tracked release proves its repository identity to the
  Tinfoil control plane with GitHub Actions OIDC; the control plane dispatches
  this workflow for only that repository.
- **Manual**: `workflow_dispatch`, optionally scoped to a single repo via
  the `repo` input; defaults to every repo in `repos.json`.

Deliberately **never** GitHub's native `schedule:` trigger — GitHub
auto-disables `schedule`-triggered workflows after 60 days of repository
inactivity, which would silently break this without an external caller
noticing. Both triggers above are externally invoked instead.

## `repos.json`

A hardcoded list for the pilot. Will be replaced by a query against
Tinfoil's control plane once the pilot's design is validated — see open
questions in the design doc.
