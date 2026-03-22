#!/usr/bin/env bash
set -euo pipefail

# Regular sync workflow for forked nullclaw repos.
#
# Default branch model:
#   main        <- rebased onto upstream/main
#   custom-main <- rebased onto main
#   release     <- rebased onto custom-main
#
# Usage:
#   scripts/sync-upstream.sh
#
# Optional overrides:
#   BASE_BRANCH=main CUSTOM_BRANCH=custom-main RELEASE_BRANCH=release scripts/sync-upstream.sh
#   SKIP_RELEASE=1 scripts/sync-upstream.sh

BASE_BRANCH="${BASE_BRANCH:-main}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-custom-main}"
RELEASE_BRANCH="${RELEASE_BRANCH:-release}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
SKIP_RELEASE="${SKIP_RELEASE:-0}"

log() {
  printf "[sync-upstream] %s\n" "$*"
}

require_branch() {
  local branch="$1"
  if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
    log "Missing local branch: ${branch}"
    exit 1
  fi
}

require_remote_ref() {
  local ref="$1"
  if ! git show-ref --verify --quiet "refs/remotes/${ref}"; then
    log "Missing remote ref: ${ref}"
    exit 1
  fi
}

require_clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Working tree is not clean. Commit or stash changes first."
    exit 1
  fi
}

main() {
  require_clean_tree

  log "Fetching remotes"
  git fetch "$UPSTREAM_REMOTE" --prune
  git fetch "$ORIGIN_REMOTE" --prune

  require_remote_ref "${UPSTREAM_REMOTE}/${BASE_BRANCH}"
  require_branch "$BASE_BRANCH"
  require_branch "$CUSTOM_BRANCH"
  if [[ "$SKIP_RELEASE" != "1" ]]; then
    require_branch "$RELEASE_BRANCH"
  fi

  log "Rebasing ${BASE_BRANCH} onto ${UPSTREAM_REMOTE}/${BASE_BRANCH}"
  git checkout "$BASE_BRANCH"
  git rebase "${UPSTREAM_REMOTE}/${BASE_BRANCH}"
  git push "$ORIGIN_REMOTE" "$BASE_BRANCH" --force-with-lease

  log "Rebasing ${CUSTOM_BRANCH} onto ${BASE_BRANCH}"
  git checkout "$CUSTOM_BRANCH"
  git rebase "$BASE_BRANCH"
  git push "$ORIGIN_REMOTE" "$CUSTOM_BRANCH" --force-with-lease

  if [[ "$SKIP_RELEASE" != "1" ]]; then
    log "Rebasing ${RELEASE_BRANCH} onto ${CUSTOM_BRANCH}"
    git checkout "$RELEASE_BRANCH"
    git rebase "$CUSTOM_BRANCH"
    git push "$ORIGIN_REMOTE" "$RELEASE_BRANCH" --force-with-lease
  else
    log "Skipping ${RELEASE_BRANCH} (SKIP_RELEASE=1)"
  fi

  log "Done"
}

main "$@"
