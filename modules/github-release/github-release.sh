#!/usr/bin/env bash
set -euo pipefail

# github-release module
# Downloads a tagged release asset from a GitHub repository.
#
# Config fields:
#   repo        - GitHub repo in "owner/repo" format
#   tag         - Release tag to download, or "latest" for the latest non-pre-release
#   assets      - Array of glob patterns to match asset filename(s) (supports *)
#   run         - (optional) Multiline bash script to run after download completes
#                 Has access to $TAG and $DEST_DIR

REPOSITORY=$(echo "$1" | jq -r 'try .["repo"]')
TAG=$(echo "$1" | jq -r 'try .["tag"]')
mapfile -t ASSET_PATTERNS < <(echo "$1" | jq -r 'try .assets[] // empty')
DEST_DIR=$(echo "$1" | jq -r 'try .["dest_dir"] // "/tmp"') # default to /tmp if not provided
RUN=$(echo "$1" | jq -r 'try .run // empty')

if [[ -z "$REPOSITORY" || "$REPOSITORY" == "null" ]]; then
    echo "ERROR: 'repo' is required (e.g. 'owner/repo')" >&2
    exit 1
fi

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    echo "ERROR: 'tag' is required (e.g. 'v1.2.3' or 'latest')" >&2
    exit 1
fi

if [[ "${#ASSET_PATTERNS[@]}" -eq 0 ]]; then
    echo "ERROR: 'assets' is required (e.g. '["*.tar.gz"]')" >&2
    exit 1
fi

GITHUB_API="https://api.github.com"
REPO_NAME="${REPOSITORY##*/}"

# Resolve the tag to the actual release tag if "latest"
if [[ "$TAG" == "latest" ]]; then
    echo "Fetching latest non-pre-release for ${REPOSITORY}..."
    RELEASE_JSON=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API}/repos/${REPOSITORY}/releases" \
    | jq 'map(select(.prerelease == false and .draft == false)) | first')

    if [[ -z "$RELEASE_JSON" || "$RELEASE_JSON" == "null" ]]; then
        echo "ERROR: No stable (non-pre-release) releases found for ${REPOSITORY}" >&2
        exit 1
    fi

    TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
    echo "Resolved latest tag: ${TAG}"
else
    echo "Fetching release ${TAG} for ${REPOSITORY}..."
    RELEASE_JSON=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API}/repos/${REPOSITORY}/releases/tags/${TAG}")

    if [[ -z "$RELEASE_JSON" || "$RELEASE_JSON" == "null" ]]; then
        echo "ERROR: Release '${TAG}' not found for ${REPOSITORY}" >&2
        exit 1
    fi
fi

# Collect all asset names and download URLs
mapfile -t ASSET_NAMES < <(echo "$RELEASE_JSON" | jq -r '.assets[].name')
mapfile -t ASSET_URLS  < <(echo "$RELEASE_JSON" | jq -r '.assets[].browser_download_url')

# Match assets against the glob patterns
mkdir -p "${DEST_DIR}"

for ASSET_PATTERN in "${ASSET_PATTERNS[@]}"; do
    MATCHED=0

    for i in "${!ASSET_NAMES[@]}"; do
        NAME="${ASSET_NAMES[$i]}"
        URL="${ASSET_URLS[$i]}"
        # Use bash glob matching via case
        # shellcheck disable=SC2254
        case "$NAME" in
            $ASSET_PATTERN)
                MATCHED=$((MATCHED + 1))
                if [[ -f "${DEST_DIR}/${NAME}" ]]; then
                    echo "Skipping '${NAME}' (already exists at ${DEST_DIR}/${NAME})"
                else
                    echo "Downloading '${NAME}' -> ${DEST_DIR}/${NAME}"
                    curl -fsSL -o "${DEST_DIR}/${NAME}" "$URL"
                    echo "Saved: ${DEST_DIR}/${NAME}"
                fi
                break
                ;;
        esac
    done

    if [[ "$MATCHED" -eq 0 ]]; then
        echo "ERROR: No assets matched patterns '${ASSET_PATTERNS[*]}' in release ${TAG} of ${REPOSITORY}" >&2
        echo "Available assets:" >&2
        printf '  %s\n' "${ASSET_NAMES[@]}" >&2
        exit 1
    fi
done


echo "github-release: downloaded ${MATCHED} asset(s) to ${DEST_DIR}"

if [[ -n "$RUN" ]]; then
    echo "github-release: running post-download script..."
    export TAG
    (cd "$DEST_DIR" && bash -euo pipefail <<< "$RUN")
fi

