#!/bin/bash
set -euo pipefail

REPO=${1:?usage: check-and-attest.sh owner/repo tag digest}
TAG=${2:?usage: check-and-attest.sh owner/repo tag digest}
DIGEST=${3:?usage: check-and-attest.sh owner/repo tag digest}
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "invalid repository name: $REPO" >&2
  exit 1
fi
if ! git check-ref-format "refs/tags/${TAG}" >/dev/null || [[ "$TAG" == -* ]]; then
  echo "invalid release tag for ${REPO}: ${TAG}" >&2
  exit 1
fi
if ! [[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  echo "invalid release digest for ${REPO}@${TAG}" >&2
  exit 1
fi

ARTIFACT=tinfoil-deployment.json
if [ "$REPO" = tinfoilsh/platform-endorsements ]; then
  ARTIFACT=platform-endorsements.json
fi

jq -n \
  --arg repo "$REPO" \
  --arg tag "$TAG" \
  --arg subject_name "$ARTIFACT" \
  --arg subject_digest "sha256:${DIGEST}" \
  '{
    format: "https://tinfoil.sh/predicate/freshness-witness/v1",
    endorses: {
      repo: $repo,
      tag: $tag,
      subject: {name: $subject_name, digest: $subject_digest}
    }
  }' >predicate.json

echo "freshness witness predicate for ${REPO}@${TAG}:"
cat predicate.json

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "subject_name=${ARTIFACT}"
    echo "subject_digest=sha256:${DIGEST}"
  } >>"$GITHUB_OUTPUT"
fi
