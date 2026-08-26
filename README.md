# Tinfoil freshness witness

Publishes a small, independently-signed **freshness witness** for the exact
repository version selected by Tinfoil's control plane. The control plane owns
repository discovery, endorsement policy, scheduling, retries, and availability.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

The control plane discovers active repositories from its container database;
this repository does not maintain a second registry.

## How it works

For the repository, tag, and artifact digest supplied by the control plane, the
workflow:

1. Constructs the existing freshness predicate for that exact tuple.
2. Publishes an [`actions/attest`](https://github.com/actions/attest)
   attestation for that release. No witness file is hosted in this repo.

The publisher intentionally does not resolve GitHub latest, fetch release
metadata, verify source attestations, or decide whether a refresh is needed.
The trusted control plane makes the endorsement decision; clients independently
verify the complete source and freshness chain before trusting it.

A verifier holding a digest for any tracked artifact looks up its freshness
witness with one call to GitHub's
Artifact Attestations API, keyed by that same digest:

```
GET https://api.github.com/repos/tinfoilsh/freshness-witness/attestations/sha256:<digest>
```

If a recent witness exists (its verified transparency-log timestamp is within the
verifier's hardcoded `MaxFreshnessAge`, currently seven days) and it is signed
by this repo's expected workflow identity, the artifact at that digest is
considered fresh.

## Witness shape

```json
{
  "format": "https://tinfoil.sh/predicate/freshness-witness/v1",
  "endorses": {
    "repo": "tinfoilsh/confidential-model-router",
    "tag": "v0.0.135",
    "subject": {
      "name": "tinfoil-deployment.json",
      "digest": "sha256:<hex>"
    }
  }
}
```

There are deliberately no publisher-controlled time fields. Verifiers use the
earliest authenticated transparency-log timestamp from GitHub's Sigstore bundle and
enforce a hardcoded seven-day maximum age.

## Triggers

- **Reconciled**: Tinfoil's control plane checks its active repository set every
  minute and dispatches this workflow when latest has no valid witness with more
  than two days remaining.
- **Promotion**: the control plane publishes the candidate's witness while it
  boots, then marks the already-endorsed release latest only when the candidate
  is accepted. Non-latest releases are not renewed.

The workflow inputs are `owner/repo`, release tag, and artifact SHA-256 digest.
GitHub requires write access to this repository to dispatch it, while the
control plane uses an Actions-write token scoped to this repository. The control
plane keeps the deduplication reservation; this workflow has no scheduling state.

During the coordinated rollout, the workflow temporarily accepts the old
repo-only request and resolves its latest release. A follow-up removes that
fallback after the control plane sends the exact tuple everywhere.

Only public repositories are supported initially. The control plane enforces
that boundary and does not hold customer-repository read tokens. Private
repository support is intentionally deferred.

Deliberately **never** GitHub's native `schedule:` trigger — GitHub
auto-disables `schedule`-triggered workflows after 60 days of repository
inactivity, which would silently break this without an external caller
noticing. Both triggers above are externally invoked instead.

Standard enclave repositories use `tinfoil-deployment.json` as the subject.
The global platform-endorsements dependency uses
`platform-endorsements.json`.
