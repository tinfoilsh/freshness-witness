#!/bin/bash
# Resolves a tracked repo's current releases/latest tag and tinfoil.hash
# digest, and writes the freshness-witness predicate for it to
# predicate.json in the current directory.
#
# Run from the repository root: ./scripts/check-and-attest.sh <owner/repo>
#
# When $GITHUB_OUTPUT is set, also emits subject_name/subject_digest/tag for
# a subsequent actions/attest step to consume.
set -euo pipefail

REPO="${1:?usage: check-and-attest.sh <owner/repo>}"

TAG=$(curl -sS "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name // empty')
if [ -z "$TAG" ]; then
  echo "no releases/latest found for ${REPO}" >&2
  exit 1
fi

DIGEST=$(curl -sSL "https://github.com/${REPO}/releases/download/${TAG}/tinfoil.hash" | tr -d '[:space:]')
if [ -z "$DIGEST" ]; then
  echo "no tinfoil.hash asset found for ${REPO}@${TAG}" >&2
  exit 1
fi

ISSUED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg repo "$REPO" \
  --arg tag "$TAG" \
  --arg digest "sha256:${DIGEST}" \
  --arg issued_at "$ISSUED_AT" \
  '{
    format: "https://tinfoil.sh/predicate/freshness-witness/v1",
    endorses: {repo: $repo, tag: $tag, digest: $digest},
    issued_at: $issued_at
  }' > predicate.json

echo "freshness witness predicate for ${REPO}@${TAG} (sha256:${DIGEST}):"
cat predicate.json

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "subject_name=${REPO}"
    echo "subject_digest=sha256:${DIGEST}"
    echo "tag=${TAG}"
  } >> "$GITHUB_OUTPUT"
fi
