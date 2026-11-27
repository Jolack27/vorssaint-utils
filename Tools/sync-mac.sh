#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Fetches the latest changes from origin (optionally switching to a given branch),
# builds the isolated "Vorssaint (Developer)" app with stable local signing,
# runs its selftest, installs it into /Applications, and launches it.
#
# Usage:
#   ./Tools/sync-mac.sh                 # pull current branch, build, install & launch
#   ./Tools/sync-mac.sh <branch-name>   # switch to <branch-name>, pull, build, install & launch
#   ./Tools/sync-mac.sh --test          # also run unit tests before installing
#   ./Tools/sync-mac.sh --release       # build & install the optimized release variant instead of --dev
#   ./Tools/sync-mac.sh --no-launch     # install without launching the app
set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH=""
RUN_TESTS=0
DEV_MODE=1
LAUNCH_APP=1

for arg in "$@"; do
    case "$arg" in
        --test)      RUN_TESTS=1 ;;
        --release)   DEV_MODE=0 ;;
        --dev)       DEV_MODE=1 ;;
        --no-launch) LAUNCH_APP=0 ;;
        -h|--help)
            sed -n '9,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "✗ Unknown option: $arg" >&2
            exit 1
            ;;
        *)
            BRANCH="$arg"
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "✗ Tools/sync-mac.sh must be run on macOS." >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "✗ Xcode Command Line Tools are missing. Install them first with:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi

echo "▸ Fetching latest changes from origin…"
git fetch --prune origin

TARGET_BRANCH="$BRANCH"
if [[ -z "$TARGET_BRANCH" ]]; then
    TARGET_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
fi

if [[ -n "$BRANCH" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "✗ Working tree has local uncommitted changes; commit or stash them before switching to '$BRANCH'." >&2
        exit 1
    fi
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git checkout "$BRANCH"
    else
        git checkout -B "$BRANCH" "origin/$BRANCH"
    fi
fi

if [[ -n "$TARGET_BRANCH" ]] && git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
    if [[ -z "$(git status --porcelain)" ]]; then
        echo "▸ Updating '$TARGET_BRANCH' from origin/$TARGET_BRANCH…"
        git pull --ff-only origin "$TARGET_BRANCH"
    else
        echo "  ⚠ Local uncommitted changes detected — building current working tree without git pull."
    fi
fi

COMMIT_SUMMARY="$(git log -1 --format='%h (%s)')"
echo "▸ Building commit $COMMIT_SUMMARY…"

if (( RUN_TESTS )); then
    echo "▸ Running unit tests…"
    ./build.sh --test
fi

if (( DEV_MODE )); then
    APP_BUNDLE="/Applications/Vorssaint (Developer).app"
    SELFTEST_BIN="build/VorssaintDeveloper"
    ./build.sh --dev --install
else
    APP_BUNDLE="/Applications/Vorssaint.app"
    SELFTEST_BIN="build/Vorssaint"
    ./build.sh --install
fi

echo "▸ Running selftest…"
"$SELFTEST_BIN" --selftest

if (( LAUNCH_APP )); then
    echo "▸ Launching $APP_BUNDLE…"
    open "$APP_BUNDLE"
fi

echo "✓ Ready: $APP_BUNDLE ($COMMIT_SUMMARY)"
