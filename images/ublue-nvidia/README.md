# osyx on Universal Blue

A bootc image that puts the osyx desktop on top of Universal Blue's
[base images](https://github.com/ublue-os/main). One Containerfile, two variants:

| Image | Base | For |
| :--- | :--- | :--- |
| `ghcr.io/ultozon/osyx-ublue` | `ghcr.io/ublue-os/base-main` | AMD and Intel graphics (Mesa) |
| `ghcr.io/ultozon/osyx-ublue-nvidia` | `ghcr.io/ublue-os/base-nvidia` | NVIDIA (proprietary driver, akmods, Secure Boot signing) |

The base image provides the drivers. This image adds Hyprland, SDDM and the
osyx tools and configs. The folder is still called `ublue-nvidia` for
historical reasons; it builds both.

Unlike the Debian bootstrap, nothing is compiled on the target machine.
Everything is built into the image, and updates arrive as a new image.

## What goes where

| Piece | Source | Lands in |
| :--- | :--- | :--- |
| Hyprland stack | COPR `sdegler/hyprland` (replaces `hypr-builder` / `gcc-builder`) | `/usr` |
| `totpyx`, `netkit`, `lookas` | built in a Rust stage from `packages/` | `/usr/bin` |
| `asryx` | built in a Fedora stage against the pinned whisper.cpp (`GGML_NATIVE=OFF`, needs AVX2) | `/usr/bin`, linked from `~/.local/bin/asryx` |
| asryx models | `base.en` + Silero VAD, downloaded on first login | `~/.local/share/asryx` |
| `thyx` | `packages/thyx` (submodule) | `/usr/share/sddm/themes/thyx`, fonts in `/usr/share/fonts/thyx` |
| thyx `theme.conf` | symlink to a writable copy (group `wheel`) so flavors can switch it | `/var/lib/osyx/thyx-theme.conf` |
| Keyboard | `config/` uses French AZERTY; `build.sh` switches it to `us` / `altgr-intl` | `hypr/input.lua` in `/etc/skel` |
| Fonts | release asset `fonts-v1.0.0` (Inter, Iosevka Fixed SS18, Meslo Nerd Font), SHA-256 pinned | `/usr/share/fonts/osyx` |
| Dotfiles | `config/` | `/etc/skel` (new users), `/usr/share/osyx/config` |
| oh-my-zsh + plugins | cloned at build time | `/etc/skel/.oh-my-zsh` |
| `flavors` | `packages/flavors` | `~/flavors` (backgrounds linked to `/usr/share/osyx/flavors`) |
| `powyx` | `packages/powyx` | installed per user on first login |
| NVIDIA session env | `files/usr/libexec/osyx-session` | set only when `nvidia_drm` is loaded |

## Build

From the repository root, with the submodules checked out:

```sh
git submodule update --init packages/thyx packages/asryx packages/lookas
podman build -f images/ublue-nvidia/Containerfile -t localhost/osyx-nvidia:latest .

# AMD / Intel
podman build -f images/ublue-nvidia/Containerfile \
  --build-arg BASE_IMAGE=ghcr.io/ublue-os/base-main -t localhost/osyx-main:latest .
```

Use `--build-arg FEDORA_VERSION=43` to pin a different Fedora release.

## Test in a VM

`vm/` turns the built image into a qcow2 and boots it in QEMU. Graphics are
software-rendered by default (`VM_GL=1` tries virgl, which shows a black window
on NVIDIA hosts). The NVIDIA path isn't exercised there, everything else is.

```sh
images/ublue-nvidia/vm/build-disk.sh   # sudo; copies the image to root storage
                                       # IMAGE=localhost/osyx-main:latest for AMD/Intel
images/ublue-nvidia/vm/run.sh          # add -snapshot to discard changes
```

Log in as `tester` / `tester` and pick the **osyx** session.

## Installer ISO

```sh
images/ublue-nvidia/iso/build-iso.sh   # sudo; writes iso/output/bootiso/osyx-nvidia-install.iso
images/ublue-nvidia/iso/test-iso.sh    # try it in a UEFI VM with an empty disk first

# AMD / Intel: from localhost/osyx-main:latest, writes osyx-main-install.iso
VARIANT=main images/ublue-nvidia/iso/build-iso.sh
VARIANT=main images/ublue-nvidia/iso/test-iso.sh
```

bootc-image-builder's ISO is unattended and wipes every disk (`clearpart --all`).
`build-iso.sh` replaces its kickstart with `iso/osyx.ks`, so the installer
asks for the disk, your user, language and time zone. Tick "Make this user
administrator" to get sudo. Installed systems track the published image of
their variant (`ghcr.io/ultozon/osyx-ublue-nvidia:latest` or
`ghcr.io/ultozon/osyx-ublue:latest`) for `bootc upgrade`.

## Use

Switch an existing Fedora Atomic / ublue install to the local image (use
`osyx-main` on AMD/Intel):

```sh
sudo bootc switch --transport containers-storage localhost/osyx-nvidia:latest
systemctl reboot
```

At the SDDM login screen, choose the **osyx** session.

Users that existed before the switch don't get the `/etc/skel` dotfiles. To
copy them (plus oh-my-zsh, `~/flavors` and the asryx link) without overwriting
files you already have, run:

```sh
/usr/libexec/osyx-user-setup --dotfiles --force
```

Switching the login screen theme through flavors works for members of `wheel`.

## CI

`.github/workflows/build-ublue.yml` builds both variants daily and on every
push to `main`, rechunks them, pushes them to `ghcr.io/ultozon/osyx-ublue` and
`ghcr.io/ultozon/osyx-ublue-nvidia` (tags `latest`, `latest-YYYYMMDD`,
`YYYYMMDD`, `YYYYMMDD-<sha>`) and signs them with cosign. Pull requests only
build. The signing key is the repository secret `SIGNING_SECRET`; the public
key is `cosign.pub` in the repository root:

```sh
cosign verify --key cosign.pub ghcr.io/ultozon/osyx-ublue:latest
cosign verify --key cosign.pub ghcr.io/ultozon/osyx-ublue-nvidia:latest
```

Switch an installed system between variants (e.g. after a GPU change):

```sh
sudo bootc switch ghcr.io/ultozon/osyx-ublue-nvidia:latest   # or osyx-ublue
systemctl reboot
```

## Not yet wired in

- `ctrlyx`: the submodule's repository (`github.com/rccyx/ctrlyx`) is not
  publicly reachable, so it can't be checked out or built. The `ALT + M`
  keybind does nothing until it is.
- `clipyx`: unreleased upstream and not a submodule yet. The `SUPER + X`
  keybind does nothing until it is published.
- `flavors` has no `wofi.css.j2` template, so it warns and skips the wofi style.
- `syncer` assumes APT and is not relevant on an image-based system.
- Signature enforcement: the image is signed, but installed systems don't
  verify it yet (no `/etc/containers/policy.json` entry for the key).
