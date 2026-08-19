# Tinfoil freshness witness

Publishes a small, independently-signed **freshness witness** per active
enclave repository, re-checked on a schedule and on demand, so verifiers can
bound how long a Sigstore-published Tinfoil artifact can be trusted without an
active re-endorsement — without needing a revocation mechanism.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

The control plane discovers active repositories from its container database;
this repository does not maintain a second registry.

## How it works

For each repository supplied by the control plane, the workflow:

1. Resolves the current latest release tag and commit, downloads its artifact,
   and checks the published `tinfoil.hash`.
2. Independently verifies the artifact's existing Sigstore attestation against
   the configured predicate and workflow identity.
3. Publishes an [`actions/attest`](https://github.com/actions/attest)
   attestation against the verified source attestation's same subject name and
   digest. No witness file is hosted in this repo.

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

- **Reconciled**: Tinfoil's control plane polls its active container repository
  set every minute. Newly active repositories are witnessed immediately and
  active repositories are renewed every five days, inside the verifier's
  seven-day maximum age. Removing and later relaunching the final replica of a
  repository triggers a new witness.
- **Event-driven**: a release proves its repository and exact tag ref to the
  Tinfoil control plane with GitHub Actions OIDC. If that repository is active,
  the control plane dispatches this workflow for its current latest release.
- **Manual**: `workflow_dispatch` accepts a JSON `repos` array and an optional
  `include_platform` flag. It always witnesses latest releases.

Deliberately **never** GitHub's native `schedule:` trigger — GitHub
auto-disables `schedule`-triggered workflows after 60 days of repository
inactivity, which would silently break this without an external caller
noticing. Both triggers above are externally invoked instead.

Standard enclave repositories publish `tinfoil-deployment.json` under the
`snp-tdx-multiplatform/v1` predicate from
`.github/workflows/tinfoil-release-publish.yml`. The workflow derives those
values from each repository name. The global platform-endorsements dependency
is included once per scheduled batch with its platform-specific artifact and
signer identity.
