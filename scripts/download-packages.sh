#!/bin/sh
# Downloads the .deb files of the newest releases of each source repository.
#
#   download-packages.sh <directory> <releases-per-repository> <owner/repo>...
#
# GitHub releases are the only place the packages are stored: the APT
# repository is rebuilt from them on every run, so nothing binary lives in git.
# Needs the GitHub CLI (`gh`) with GH_TOKEN set; on GitHub Actions that is
# preinstalled and the workflow's token is enough for public repositories.
set -eu

if [ "$#" -lt 3 ]; then
    echo "usage: $0 <directory> <releases-per-repository> <owner/repo>..." >&2
    exit 2
fi
directory="$1"
releases_per_repository="$2"
shift 2

mkdir -p "$directory"
for repository in "$@"; do
    tags="$(gh release list --repo "$repository" --limit "$releases_per_repository" \
        --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName')"
    if [ -z "$tags" ]; then
        echo "$repository: no releases yet"
        continue
    fi
    for tag in $tags; do
        echo "$repository: $tag"
        gh release download "$tag" --repo "$repository" --pattern '*.deb' --dir "$directory" --clobber
    done
done
