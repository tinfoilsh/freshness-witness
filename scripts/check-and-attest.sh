#!/bin/bash
set -euo pipefail

TARGET=${1:?usage: check-and-attest.sh '<repos.json object>'}
REPO=$(jq -er '.repo' <<<"$TARGET")
ARTIFACT=$(jq -er '.artifact' <<<"$TARGET")
PREDICATE_TYPE=$(jq -er '.predicate_type' <<<"$TARGET")
SIGNER_WORKFLOW=$(jq -er '.signer_workflow' <<<"$TARGET")

TAG=${REQUESTED_TAG:-}
if [ -z "$TAG" ]; then
  TAG=$(gh api "repos/${REPO}/releases/latest" --jq '.tag_name')
fi
if ! git check-ref-format "refs/tags/${TAG}" >/dev/null || [[ "$TAG" == -* ]]; then
  echo "invalid release tag for ${REPO}: ${TAG}" >&2
  exit 1
fi
COMMIT=$(gh api "repos/${REPO}/commits/${TAG}" --jq '.sha')
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid commit resolved for ${REPO}@${TAG}: ${COMMIT}" >&2
  exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
gh release download "$TAG" --repo "$REPO" --dir "$workdir" --pattern "$ARTIFACT" --pattern tinfoil.hash

DIGEST=$(tr -d '[:space:]' <"$workdir/tinfoil.hash")
if ! [[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  echo "invalid tinfoil.hash for ${REPO}@${TAG}" >&2
  exit 1
fi
ACTUAL_DIGEST=$(sha256sum "$workdir/$ARTIFACT" | cut -d ' ' -f 1)
if [ "$ACTUAL_DIGEST" != "$DIGEST" ]; then
  echo "release digest mismatch for ${REPO}@${TAG}: expected ${DIGEST}, got ${ACTUAL_DIGEST}" >&2
  exit 1
fi

gh attestation verify "$workdir/$ARTIFACT" \
  --repo "$REPO" \
  --predicate-type "$PREDICATE_TYPE" \
  --signer-workflow "$SIGNER_WORKFLOW" \
  --source-ref "refs/tags/${TAG}" \
  --deny-self-hosted-runners \
  --format json >"$workdir/verification.json"

SUBJECT_NAME=$(jq -er '
  [.[].verificationResult.statement.subject[].name] | unique |
  if length == 1 then .[0] else error("verified attestations disagree on subject name") end
' "$workdir/verification.json")

jq -n \
  --arg repo "$REPO" \
  --arg tag "$TAG" \
  --arg commit "$COMMIT" \
  --arg subject_name "$SUBJECT_NAME" \
  --arg subject_digest "sha256:${DIGEST}" \
  '{
    format: "https://tinfoil.sh/predicate/freshness-witness/v1",
    endorses: {
      repo: $repo,
      tag: $tag,
      commit: $commit,
      subject: {name: $subject_name, digest: $subject_digest}
    }
  }' >predicate.json

echo "freshness witness predicate for ${REPO}@${TAG} (${COMMIT}):"
cat predicate.json

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "subject_name=${SUBJECT_NAME}"
    echo "subject_digest=sha256:${DIGEST}"
  } >>"$GITHUB_OUTPUT"
fi
