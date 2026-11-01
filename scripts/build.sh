#!/bin/bash
# Builds stock images with podman, as images.toml describes them, and tags
# each localhost/ghostrack-images/<name>:<version>.
#
#   scripts/build.sh [NAME[:VERSION]...]     (every image without arguments)
#
# A bare name builds every version of it (debian: Debian 13 and 12).
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib.sh
. "${repo}/scripts/lib.sh"

command -v podman > /dev/null || { echo "build.sh: podman is not installed" >&2; exit 1; }
selected=$(select_images "$@")
revision=$(git -C "${repo}" rev-parse HEAD 2> /dev/null || echo unknown)

while IFS=$'\t' read -r -u 3 name version family _init _stop base display_name memory level; do
    tag=$(image_tag "${name}" "${version}")
    echo "build.sh: ${tag} from ${base}"
    podman build \
        --platform linux/amd64 \
        --squash \
        --file "${repo}/images/${family}/Containerfile" \
        --build-arg "BASE=${base}" \
        --build-arg "VERSION=${version}" \
        --build-arg "TITLE=${display_name}" \
        --build-arg "REVISION=${revision}" \
        --build-arg "MINIMUM_MEMORY_BYTES=${memory}" \
        --build-arg "X86_64_LEVEL=${level}" \
        --tag "${tag}" \
        "${repo}"
done 3<<< "${selected}"
