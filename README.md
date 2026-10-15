# Tinfoil fresh endorsements

Publishes a small, independently-signed **fresh endorsement** for the exact
repository version selected by Tinfoil's control plane. The control plane owns
repository discovery, endorsement policy, scheduling, retries, and availability.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

The control plane discovers active repositories from its container database;
this repository does not maintain a second registry.

## How it works

For the repository, tag, and artifact digest supplied by the control plane, the
workflow:

1. Resolves the supplied exact tag to its Git commit and constructs the
   freshness predicate for that repository, tag, commit, and artifact digest.
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
    "commit": "<40-character Git commit>",
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

- **Reconciled**: Tinfoil's control plane renews latest and explicitly selected
  versions when their fresh endorsements enter the renewal window. Selected
  versions stop renewing when the organization's last running replica stops.
- **Manual refresh**: the Containers dashboard can request an exact version's
  fresh endorsement when it is missing, expired, or within the renewal window.
  The control plane owns the [lifetime and renewal constants](https://github.com/tinfoilsh/controlplane/blob/main/constants/freshness.go).
- **Switching latest**: when requested for a deploy, the control plane first
  dispatches an exact endorsement and then immediately marks that release
  latest. Deployment launch and acceptance never wait for witness publication.

Concurrent requests are grouped by repository, tag, and digest so different
versions do not replace each other's pending workflow runs.

The workflow inputs are `owner/repo`, release tag, and artifact SHA-256 digest.
GitHub requires write access to this repository to dispatch it, while the
control plane uses an Actions-write token scoped to this repository. The control
plane keeps the deduplication reservation; this workflow has no scheduling state.

Only public repositories are supported initially. The control plane enforces
that boundary and does not hold customer-repository read tokens. Private
repository support is intentionally deferred.

Deliberately **never** GitHub's native `schedule:` trigger — GitHub
auto-disables `schedule`-triggered workflows after 60 days of repository
inactivity, which would silently break this without an external caller
noticing. The triggers above are externally invoked instead.

Standard enclave repositories use `tinfoil-deployment.json` as the subject.
The global platform-endorsements dependency uses
`platform-endorsements.json`.
