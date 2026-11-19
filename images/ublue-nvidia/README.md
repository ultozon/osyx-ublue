# osyx on Universal Blue (NVIDIA)

A bootc image that puts the osyx desktop on top of
[`ghcr.io/ublue-os/base-nvidia`](https://github.com/ublue-os/main). The base
image provides the drivers, akmods and Secure Boot signing. This image adds Hyprland, SDDM and
the osyx tools and configs.

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
```

Use `--build-arg FEDORA_VERSION=43` to pin a different Fedora release.

## Test in a VM

`vm/` turns the built image into a qcow2 and boots it in QEMU. Graphics are
software-rendered by default (`VM_GL=1` tries virgl, which shows a black window
on NVIDIA hosts). The NVIDIA path isn't exercised there, everything else is.

```sh
images/ublue-nvidia/vm/build-disk.sh   # sudo; copies the image to root storage
images/ublue-nvidia/vm/run.sh          # add -snapshot to discard changes
```

Log in as `tester` / `tester` and pick the **osyx** session.

## Use

Switch an existing Fedora Atomic / ublue NVIDIA install to the local image:

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

## Not yet wired in

- `ctrlyx`: the submodule's repository (`github.com/rccyx/ctrlyx`) is not
  publicly reachable, so it can't be checked out or built. The `ALT + M`
  keybind does nothing until it is.
- `flavors` has no `wofi.css.j2` template, so it warns and skips the wofi style.
- `syncer` assumes APT and is not relevant on an image-based system.
- CI: push to GHCR and sign with cosign, following the
  [ublue image-template](https://github.com/ublue-os/image-template), so that
  machines can `bootc switch ghcr.io/<owner>/osyx-nvidia`.
- ISO: `bootc-image-builder` can produce an installer from the image.
