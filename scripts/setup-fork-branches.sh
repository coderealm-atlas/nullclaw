#!/usr/bin/env bash
set -e

# One-time setup for fork + upstream branch layout.
# Default model:
#   upstream-base <- clean upstream/main mirror
#   release       <- your customized branch for builds
#
# Usage:
#   scripts/setup-fork-branches.sh
#   FORK_URL="https://github.com/<you>/nullclaw.git" \
#   UPSTREAM_URL="https://github.com/nullclaw/nullclaw.git" \
#   scripts/setup-fork-branches.sh

FORK_URL="${FORK_URL:-https://github.com/coderealm-atlas/nullclaw.git}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/nullclaw/nullclaw.git}"
UPSTREAM_MAIN_BRANCH="${UPSTREAM_MAIN_BRANCH:-main}"
BASE_BRANCH="${BASE_BRANCH:-upstream-base}"
RELEASE_BRANCH="${RELEASE_BRANCH:-release}"

log() {
  printf "[setup-fork] %s\n" "$*"
}

require_clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Working tree is not clean. Commit or stash changes first."
    exit 1
  fi
}

verify_remote_url() {
  local name="$1"
  local url="$2"
  if ! git ls-remote --heads "$url" >/dev/null 2>&1; then
    log "Cannot access ${name} remote URL: ${url}"
    if [[ "$name" == "upstream" ]]; then
      log "Hint: official upstream is usually https://github.com/nullclaw/nullclaw.git"
    fi
    exit 1
  fi
}

set_or_add_remote() {
  local name="$1"
  local url="$2"
  if git remote get-url "$name" >/dev/null 2>&1; then
    git remote set-url "$name" "$url"
  else
    git remote add "$name" "$url"
  fi
}

checkout_or_create_from() {
  local branch="$1"
  local start_point="$2"
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    git switch "$branch"
  else
    git switch -c "$branch" "$start_point"
  fi
}

main() {
  require_clean_tree

  log "Validating remote URLs"
  verify_remote_url origin "$FORK_URL"
  verify_remote_url upstream "$UPSTREAM_URL"

  log "Configuring remotes"
  set_or_add_remote origin "$FORK_URL"
  set_or_add_remote upstream "$UPSTREAM_URL"

  log "Fetching remotes"
  git fetch --all --prune

  if ! git show-ref --verify --quiet "refs/remotes/upstream/${UPSTREAM_MAIN_BRANCH}"; then
    log "Missing upstream branch: upstream/${UPSTREAM_MAIN_BRANCH}"
    exit 1
  fi

  log "Preparing ${BASE_BRANCH} from upstream/${UPSTREAM_MAIN_BRANCH}"
  checkout_or_create_from "$BASE_BRANCH" "upstream/${UPSTREAM_MAIN_BRANCH}"
  git merge --ff-only "upstream/${UPSTREAM_MAIN_BRANCH}"
  git push -u origin "$BASE_BRANCH"

  log "Preparing ${RELEASE_BRANCH} from ${BASE_BRANCH}"
  checkout_or_create_from "$RELEASE_BRANCH" "$BASE_BRANCH"
  git push -u origin "$RELEASE_BRANCH"

  log "Done"
  log "Branch model:"
  log "  ${BASE_BRANCH} is the clean upstream sync branch"
  log "  ${RELEASE_BRANCH} carries your custom patches"
}

main "$@"
