#!/bin/sh
# Builds a signed APT repository from a directory of .deb files.
#
#   build-repository.sh <packages-directory> <output-directory>
#
# Environment:
#   SIGNING_KEY_ID   the GnuPG key (already imported) that signs the repository
#   UNSIGNED=1       local experiments only: skip signing; apt then refuses the
#                    repository unless it is marked [trusted=yes]
#
# Layout of the result, the standard Debian one that apt expects:
#   pool/main/<package>/<package>_<version>_<arch>.deb
#   dists/stable/Release, InRelease (signed inline), Release.gpg (detached)
#   dists/stable/main/binary-<arch>/Packages, Packages.gz, Packages.xz
#   remoteplayer-archive-keyring.gpg / .asc   the public key for the Pis
set -eu

SUITE="stable"
COMPONENT="main"
ARCHITECTURES="amd64 arm64 armhf"

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <packages-directory> <output-directory>" >&2
    exit 2
fi
packages="$1"
output="$2"
template="$(cd "$(dirname "$0")/../site-template" && pwd)"

if [ "${UNSIGNED:-0}" != "1" ] && [ -z "${SIGNING_KEY_ID:-}" ]; then
    echo "SIGNING_KEY_ID is not set (UNSIGNED=1 builds an unsigned repository for local tests)" >&2
    exit 2
fi

rm -rf "$output"
mkdir -p "$output/dists/$SUITE"

# The pool: one directory per package, named after the package's own control
# fields rather than the downloaded file name.
count=0
for deb in "$packages"/*.deb; do
    [ -e "$deb" ] || continue
    package="$(dpkg-deb --field "$deb" Package)"
    version="$(dpkg-deb --field "$deb" Version)"
    architecture="$(dpkg-deb --field "$deb" Architecture)"
    mkdir -p "$output/pool/$COMPONENT/$package"
    cp "$deb" "$output/pool/$COMPONENT/$package/${package}_${version}_${architecture}.deb"
    count=$((count + 1))
done
echo "$count packages in the pool"

# apt-ftparchive writes paths relative to the current directory into the
# indexes ("Filename: pool/..."), so it runs from the repository root.
cd "$output"
for architecture in $ARCHITECTURES; do
    index="dists/$SUITE/$COMPONENT/binary-$architecture"
    mkdir -p "$index"
    if [ -d "pool" ]; then
        apt-ftparchive --arch "$architecture" packages "pool/$COMPONENT" > "$index/Packages"
    else
        : > "$index/Packages"
    fi
    gzip --best --keep --no-name "$index/Packages"
    xz --best --keep "$index/Packages"
    echo "$architecture: $(grep -c '^Package:' "$index/Packages" || true) entries"
done

# No Valid-Until: the repository changes only with releases, and an expiring
# Release file would make unattended Pis stop updating.
apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=remoteplayer" \
    -o "APT::FTPArchive::Release::Label=remoteplayer" \
    -o "APT::FTPArchive::Release::Suite=$SUITE" \
    -o "APT::FTPArchive::Release::Codename=$SUITE" \
    -o "APT::FTPArchive::Release::Architectures=$ARCHITECTURES" \
    -o "APT::FTPArchive::Release::Components=$COMPONENT" \
    -o "APT::FTPArchive::Release::Description=remoteplayer: REST API and state watcher for mpv on a Raspberry Pi" \
    release "dists/$SUITE" > Release.tmp
mv Release.tmp "dists/$SUITE/Release"

if [ "${UNSIGNED:-0}" = "1" ]; then
    echo "warning: the repository is NOT signed" >&2
else
    gpg --batch --yes --local-user "$SIGNING_KEY_ID" --clearsign \
        --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"
    gpg --batch --yes --local-user "$SIGNING_KEY_ID" --armor --detach-sign \
        --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
    # Binary for /usr/share/keyrings (Signed-By=), armored for reading.
    gpg --batch --yes --export "$SIGNING_KEY_ID" > remoteplayer-archive-keyring.gpg
    gpg --batch --yes --armor --export "$SIGNING_KEY_ID" > remoteplayer-archive-keyring.asc
fi

cp "$template/index.html" "$template/remoteplayer.sources" .
