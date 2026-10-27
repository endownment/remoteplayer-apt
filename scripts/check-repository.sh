#!/bin/sh
# Reads a built repository the way a Raspberry Pi will: apt, in a private
# directory, verifies the signature with the exported keyring and resolves
# every package in the pool for each architecture. Fails on any warning, so a
# broken signature or index never gets published.
#
#   check-repository.sh <repository-directory>
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <repository-directory>" >&2
    exit 2
fi
repository="$(cd "$1" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/etc/apt/sources.list.d" "$work/etc/apt/preferences.d" \
    "$work/lists/partial" "$work/cache/archives/partial"
: > "$work/status"

if [ -f "$repository/remoteplayer-archive-keyring.gpg" ]; then
    trust="signed-by=$repository/remoteplayer-archive-keyring.gpg"
else
    echo "warning: no keyring, checking as an unsigned repository" >&2
    trust="trusted=yes"
fi
echo "deb [arch=amd64,arm64,armhf $trust] file:$repository stable main" > "$work/etc/apt/sources.list"

# Everything apt would read or write on a real system points into $work; it
# downloads as the current user (the _apt sandbox user cannot enter $work).
check_apt() {
    "$@" \
        -o Dir::Etc="$work/etc/apt" \
        -o Dir::State::Lists="$work/lists" \
        -o Dir::State::status="$work/status" \
        -o Dir::Cache="$work/cache" \
        -o APT::Architecture=amd64 \
        -o APT::Architectures::=amd64 -o APT::Architectures::=arm64 -o APT::Architectures::=armhf \
        -o Debug::NoLocking=true \
        -o APT::Sandbox::User="$(id -un)"
}

check_apt apt-get update > "$work/update.log" 2>&1 || true
cat "$work/update.log"
if grep -Eq '^(W|E|Err):' "$work/update.log"; then
    echo "apt reported problems with the repository" >&2
    exit 1
fi

for deb in "$repository"/pool/*/*/*.deb; do
    [ -e "$deb" ] || continue
    package="$(dpkg-deb --field "$deb" Package)"
    version="$(dpkg-deb --field "$deb" Version)"
    architecture="$(dpkg-deb --field "$deb" Architecture)"
    check_apt apt-cache show "$package:$architecture=$version" > /dev/null
    echo "ok: $package $version $architecture"
done
