# remoteplayer-apt

The APT repository of **remoteplayer**, published on GitHub Pages at
<https://endownment.github.io/remoteplayer-apt/>:

| Package | Source |
|---|---|
| `remoteplayer-restservice` | [endownment/remoteplayer-restservice](https://github.com/endownment/remoteplayer-restservice) |
| `remoteplayer-mpvwatcher` | [endownment/remoteplayer-mpvwatcher](https://github.com/endownment/remoteplayer-mpvwatcher) |

Architectures `arm64` (64-bit Raspberry Pi OS), `armhf` (32-bit, Pi 2 and
newer) and `amd64`. One suite, `stable`, serves Debian 12 "bookworm" and 13
"trixie" alike: the binaries are built against glibc 2.36.

## Using it on a Raspberry Pi

```sh
sudo curl -fsSLo /usr/share/keyrings/remoteplayer-archive-keyring.gpg \
    https://endownment.github.io/remoteplayer-apt/remoteplayer-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/remoteplayer.sources \
    https://endownment.github.io/remoteplayer-apt/remoteplayer.sources
sudo apt update
sudo apt install remoteplayer-restservice remoteplayer-mpvwatcher
```

The key is used for this repository only (`Signed-By:` in
[`remoteplayer.sources`](site-template/remoteplayer.sources)), not trusted for
any other one. After installing, follow "Installation" in the
remoteplayer-restservice README: set the API token, enable the units.

Updates come with `sudo apt upgrade`. For automatic updates with
`unattended-upgrades` (not set up by default for repositories outside
Debian), allow this origin:

```sh
echo 'Unattended-Upgrade::Origins-Pattern:: "origin=remoteplayer";' | \
    sudo tee /etc/apt/apt.conf.d/51remoteplayer-unattended
```

The last three releases of each package stay available:
`apt list -a remoteplayer-restservice`, then `sudo apt install remoteplayer-restservice=<version>`.

## How it works

Nothing binary is stored in this repository. The packages live in the GitHub
releases of the source repositories, and [`publish.yml`](.github/workflows/publish.yml)
rebuilds the whole APT repository from them on every run:

1. [`scripts/download-packages.sh`](scripts/download-packages.sh) — the
   `.deb` files of the newest three releases of each source repository;
2. [`scripts/build-repository.sh`](scripts/build-repository.sh) — the
   standard layout (`pool/`, `dists/stable/...`), indexes with
   `apt-ftparchive`, `InRelease` and `Release.gpg` signed with the key from
   the secret `APT_SIGNING_KEY`, the public keyring;
3. [`scripts/check-repository.sh`](scripts/check-repository.sh) — reads the
   result with apt itself, verifying the signature and every package for
   every architecture; any warning stops the run before publishing;
4. the result is deployed to GitHub Pages.

It runs when a source repository publishes a release (its release job sends
a `repository_dispatch`), once a day as a fallback, on a push here, and by
hand (Actions → publish → Run workflow).

## Setting up (once)

1. **Pages.** The repository must be public (Pages of private repositories
   need a paid plan, and APT cannot authenticate anyway). Settings → Pages →
   Build and deployment → Source: **GitHub Actions**.

2. **Signing key.** Create it on a trusted machine, not on GitHub:

   ```sh
   export GNUPGHOME="$(mktemp -d)"
   gpg --batch --passphrase '' --quick-gen-key "remoteplayer APT repository" ed25519 sign never
   gpg --armor --export-secret-keys > remoteplayer-apt-signing-key.asc
   ```

   Paste the contents of `remoteplayer-apt-signing-key.asc` as the secret
   `APT_SIGNING_KEY` (Settings → Secrets and variables → Actions → New
   repository secret). Keep the file in a safe place offline: with a new key
   every Pi has to download the keyring again. The key never expires on
   purpose — an expired key would silently stop updates on unattended Pis.
   Then delete the temporary `GNUPGHOME`.

3. **Release notification** (optional; without it new releases appear within
   a day). Create a fine-grained personal access token (GitHub → Settings →
   Developer settings → Fine-grained tokens) with access to
   `endownment/remoteplayer-apt` only and the permission **Contents: Read and
   write**. Add it as the secret `APT_REPOSITORY_TOKEN` to both source
   repositories.

4. Run the workflow once by hand and open the page.

## Testing locally

Needs `apt-utils`, `dpkg-dev`, `gnupg`, `xz-utils`. With `.deb` files in a
directory, a throw-away key and no network:

```sh
export GNUPGHOME="$(mktemp -d)"
gpg --batch --passphrase '' --quick-gen-key "test" ed25519 sign never
export SIGNING_KEY_ID="$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')"
scripts/build-repository.sh path/to/debs site
scripts/check-repository.sh site
```

`scripts/download-packages.sh downloads 3 endownment/remoteplayer-restservice`
fetches real releases (GitHub CLI, logged in or `GH_TOKEN` set).
