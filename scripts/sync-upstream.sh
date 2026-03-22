#!/usr/bin/env bash
set -e

# Regular sync workflow for forked nullclaw repos.
#
# Default branch model:
#   upstream-base <- fast-forwarded to upstream/main
#   release       <- rebased onto upstream-base
#
# Usage:
#   scripts/sync-upstream.sh
#
# Optional overrides:
#   BASE_BRANCH=upstream-base RELEASE_BRANCH=release scripts/sync-upstream.sh
#   PUSH_BASE=1 PUSH_RELEASE=1 scripts/sync-upstream.sh

UPSTREAM_MAIN_BRANCH="${UPSTREAM_MAIN_BRANCH:-main}"
BASE_BRANCH="${BASE_BRANCH:-upstream-base}"
RELEASE_BRANCH="${RELEASE_BRANCH:-release}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
PUSH_BASE="${PUSH_BASE:-1}"
PUSH_RELEASE="${PUSH_RELEASE:-1}"

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

  require_remote_ref "${UPSTREAM_REMOTE}/${UPSTREAM_MAIN_BRANCH}"
  require_branch "$BASE_BRANCH"
  require_branch "$RELEASE_BRANCH"

  log "Fast-forwarding ${BASE_BRANCH} to ${UPSTREAM_REMOTE}/${UPSTREAM_MAIN_BRANCH}"
  git switch "$BASE_BRANCH"
  git merge --ff-only "${UPSTREAM_REMOTE}/${UPSTREAM_MAIN_BRANCH}"
  if [ "$PUSH_BASE" = "1" ]; then
    git push "$ORIGIN_REMOTE" "$BASE_BRANCH"
  else
    log "Skipping push for ${BASE_BRANCH} (PUSH_BASE=0)"
  fi

  log "Rebasing ${RELEASE_BRANCH} onto ${BASE_BRANCH}"
  git switch "$RELEASE_BRANCH"
  git rebase "$BASE_BRANCH"
  if [ "$PUSH_RELEASE" = "1" ]; then
    git push "$ORIGIN_REMOTE" "$RELEASE_BRANCH" --force-with-lease
  else
    log "Skipping push for ${RELEASE_BRANCH} (PUSH_RELEASE=0)"
  fi

  log "Done"
}

main "$@"
