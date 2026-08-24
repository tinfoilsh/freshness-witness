# Tinfoil freshness witness

Publishes a small, independently-signed **freshness witness** for a repository's
current latest release. Tinfoil's control plane owns repository discovery,
scheduling, retries, and availability policy.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

The control plane discovers active repositories from its container database;
this repository does not maintain a second registry.

## How it works

For the repository supplied by the control plane, the workflow:

1. Resolves the current latest release tag and commit inside the trusted GitHub
   worker.
2. Reads the release's `tinfoil.hash`.
3. Publishes an [`actions/attest`](https://github.com/actions/attest)
   attestation for that release. No witness file is hosted in this repo.

The publisher intentionally does not verify the source attestation or decide
whether a refresh is needed. Controlplane performs those checks before
dispatching, and clients independently verify the complete source and freshness
chain before trusting it. Invalid release metadata therefore produces evidence
that verifiers reject rather than expanding this signing workflow's policy.

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

- **Reconciled**: Tinfoil's control plane checks its active repository set every
  minute and dispatches this workflow when latest has no valid witness with more
  than two days remaining.
- **Promotion**: promoting a release changes GitHub latest. The same reconciler
  observes that change and publishes the new witness; promotion waits for the
  resulting evidence.

The workflow has one input: `owner/repo`. GitHub requires write access to this
repository to dispatch it, while the control plane uses an Actions-write token
scoped to this repository. Controlplane keeps the deduplication reservation;
this trusted workflow does not need scheduling state.

The worker mints a contents-read installation token restricted to that one
repository using the same GitHub App customers install during dashboard
onboarding. This lets private repositories use the identical flow without
giving the control plane a tag, digest, or token input. The
`CONTROLPLANE_GITHUB_APP_CLIENT_ID` repository variable and
`CONTROLPLANE_GITHUB_APP_PRIVATE_KEY` repository secret configure that App.

Deliberately **never** GitHub's native `schedule:` trigger — GitHub
auto-disables `schedule`-triggered workflows after 60 days of repository
inactivity, which would silently break this without an external caller
noticing. Both triggers above are externally invoked instead.

Standard enclave repositories use `tinfoil-deployment.json` as the subject.
The global platform-endorsements dependency uses
`platform-endorsements.json`.
