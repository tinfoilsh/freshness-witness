#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export REAL_GIT
REAL_GIT=$(command -v git)
mkdir "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/git" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$1" == check-ref-format ]]; then
  exec "$REAL_GIT" "$@"
fi
[[ "$1" == ls-remote && -z "${GH_TOKEN:-}" ]]
printf '%s\trefs/tags/v1\n' "$TEST_COMMIT"
if [[ -n "${TEST_PEELED_COMMIT:-}" ]]; then
  printf '%s\trefs/tags/v1^{}\n' "$TEST_PEELED_COMMIT"
fi
EOF
cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$*" == 'api repos/owner/repo/commits/v1 --jq .sha' && "$GH_TOKEN" == scoped-token ]]
echo "$TEST_COMMIT"
EOF
chmod +x "$TEST_DIR/bin/"*
export PATH="$TEST_DIR/bin:$PATH"
export TEST_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export TEST_PEELED_COMMIT=
export GH_TOKEN=
export GITHUB_OUTPUT="$TEST_DIR/output"
DIGEST=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
cd "$TEST_DIR"

check_predicate() {
  local repo=$1 expected_commit=$2 artifact=$3
  "$SCRIPT_DIR/check-and-attest.sh" "$repo" v1 "$DIGEST" >/dev/null
  jq -e --arg repo "$repo" --arg commit "$expected_commit" --arg artifact "$artifact" --arg digest "sha256:$DIGEST" '
    .format == "https://tinfoil.sh/predicate/freshness-witness/v1" and
    .endorses == {repo: $repo, tag: "v1", commit: $commit, subject: {name: $artifact, digest: $digest}}
  ' predicate.json >/dev/null
}

check_predicate owner/repo "$TEST_COMMIT" tinfoil-deployment.json
TEST_PEELED_COMMIT=cccccccccccccccccccccccccccccccccccccccc
check_predicate owner/repo "$TEST_PEELED_COMMIT" tinfoil-deployment.json
check_predicate tinfoilsh/platform-endorsements "$TEST_PEELED_COMMIT" platform-endorsements.json
GH_TOKEN=scoped-token
check_predicate owner/repo "$TEST_COMMIT" tinfoil-deployment.json

reject() {
  if "$SCRIPT_DIR/check-and-attest.sh" "$@" >/dev/null 2>&1; then
    echo "expected invalid witness input to fail" >&2
    exit 1
  fi
}
reject ../repo v1 "$DIGEST"
reject owner/repo ../v1 "$DIGEST"
reject owner/repo -v1 "$DIGEST"
reject owner/repo v1 invalid-digest
TEST_COMMIT=invalid-commit
reject owner/repo v1 "$DIGEST"
echo "freshness predicate tests passed"
