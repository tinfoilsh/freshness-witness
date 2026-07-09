# Tinfoil freshness witness

Publishes a small, independently-signed **freshness witness** per tracked
repo, re-checked on a schedule and on demand, so verifiers can bound how
long a Sigstore-published Tinfoil artifact can be trusted without an active
re-endorsement — without needing a revocation mechanism.

Predicate: `https://tinfoil.sh/predicate/freshness-witness/v1`

Design background and open questions:
[`PLATFORM_FRESHNESS_PILOT.md`](https://github.com/tinfoilsh/workspace-attestation/blob/main/sdk-flywheel/v3/PLATFORM_FRESHNESS_PILOT.md)
in the `workspace-attestation` monorepo.

Status: **pilot**, tracking `tinfoilsh/platform-endorsements` only.

## How it works

For each tracked repo (`repos.json`), the workflow:

1. Resolves the repo's current `releases/latest` tag and the digest of its
   `tinfoil.hash` release asset.
2. Publishes an [`actions/attest`](https://github.com/actions/attest)
   attestation **directly against that digest** (`subject-digest`, no
   `subject-path`) — no witness file is hosted in this repo. The subject
   digest is whatever the tracked repo's release already published; this
   repo only vouches that it re-checked it recently.

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
    "tag": "v0.3.1",
    "digest": "sha256:<hex>"
  },
  "issued_at": "2026-07-08T00:00:00Z"
}
```

There is deliberately **no `expires_at` field** — the trust window is a
hardcoded constant in each verifier, not something this repo's pipeline
gets to declare. See the design doc for the full rationale.

## Triggers

- **Scheduled**: dispatched externally by Tinfoil's control plane on a
  cadence tighter than the verifier-side `MaxFreshnessAge` (e.g. every 5–6
  days), re-signing every tracked repo unconditionally — this is the
  heartbeat that keeps witnesses from aging out.
- **Event-driven**: `repository_dispatch` (`freshness-check` event type),
  fired by a tracked repo's own release workflow right after it publishes a
  new release — same convention as `platform-endorsements/build.yml`'s
  existing legacy-republish trigger. Only the affected repo is re-checked.
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
