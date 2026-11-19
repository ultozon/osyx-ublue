#!/usr/bin/env bash
# Runs inside the image build. Layers the osyx desktop onto a ublue NVIDIA base.
set -Eeuo pipefail

COPRS=(
  sdegler/hyprland  # Hyprland >= 0.56 (Lua configs)
  atim/starship     # prompt used by config/zsh/tools.zsh
)

# Build fails if any of these is missing.
REQUIRED_PACKAGES=(
  # compositor stack (COPR)
  hyprland hyprlock hypridle hyprpaper hyprsunset hyprshutdown
  xdg-desktop-portal-hyprland hyprpolkitagent
  # login
  sddm
  # shell: config/.zshrc sources oh-my-zsh (shipped in /etc/skel), starship
  zsh git starship fd-find
  # session tools used by the osyx configs
  kitty tmux mako wofi neovim fzf jq libnotify
  wl-clipboard grim slurp brightnessctl playerctl iwd pipewire-utils
  xdg-desktop-portal-gtk
  # flavors theme generator
  python3 python3-jinja2
  # Qt/QML runtime for powyx and the thyx SDDM theme (video background).
  # Fedora ships the `qml` runner only in the -devel subpackage.
  qt6-qtdeclarative qt6-qtdeclarative-devel qt6-qt5compat qt6-qtsvg qt6-qtwayland
  qt6-qtmultimedia fontconfig
)

# Nice to have; skipped with a warning when the repos don't carry them.
OPTIONAL_PACKAGES=(
  lsd swappy waypaper cliphist
)

log() { printf '[osyx-build] %s\n' "$*"; }

for copr in "${COPRS[@]}"; do
  log "enabling COPR $copr"
  dnf5 -y copr enable "$copr"
done

log "installing required packages"
dnf5 -y install "${REQUIRED_PACKAGES[@]}"

log "installing optional packages"
dnf5 -y install --skip-unavailable "${OPTIONAL_PACKAGES[@]}"

# Don't leave the COPRs enabled on deployed systems; updates come with the image.
for copr in "${COPRS[@]}"; do
  dnf5 -y copr disable "$copr"
done

# powyx looks for `qml6` or `qml`; Fedora names it `qml-qt6`.
if ! command -v qml6 >/dev/null 2>&1 && ! command -v qml >/dev/null 2>&1; then
  for candidate in /usr/bin/qml-qt6 /usr/lib64/qt6/bin/qml /usr/lib/qt6/bin/qml; do
    if [[ -x "$candidate" ]]; then
      ln -s "$candidate" /usr/bin/qml6
      break
    fi
  done
  command -v qml6 >/dev/null 2>&1 || { log "no QML runner found"; exit 1; }
fi

# --- thyx (SDDM theme) -------------------------------------------------------
# flavors switches the login theme by overwriting thyx/theme.conf as the user.
# /usr is read-only, so the live file sits in /var (group wheel, see
# tmpfiles.d/osyx.conf) and the theme dir links to it.
THYX=/usr/share/sddm/themes/thyx
[[ -f "$THYX/metadata.desktop" ]] || { log "thyx missing: run git submodule update --init"; exit 1; }
mv "$THYX/theme.conf" "$THYX/theme.conf.default"
ln -s /var/lib/osyx/thyx-theme.conf "$THYX/theme.conf"
fc-cache -f /usr/share/fonts/thyx >/dev/null

# osyx fonts (Containerfile stage `fonts`).
fc-cache -f /usr/share/fonts/osyx >/dev/null

# --- per-user defaults (/etc/skel) ------------------------------------------
# Keyboard: US international with AltGr dead keys instead of osyx's French
# AZERTY. The AZERTY workspace binds stay; they just never match.
HYPR_INPUT=/usr/share/osyx/config/.config/hypr/input.lua
grep -q 'kb_layout = "fr",' "$HYPR_INPUT" || { log "kb_layout line not found in $HYPR_INPUT"; exit 1; }
sed -i \
  -e 's|^-- French keyboard layout.*|-- US international, AltGr dead keys (set by the osyx image build).|' \
  -e 's|kb_layout = "fr",|kb_layout = "us",\n        kb_variant = "altgr-intl",|' \
  "$HYPR_INPUT"

# kitty: Fedora's Tibetan font Jomolhari covers Private Use Area codepoints,
# and kitty's fallback picks it over Meslo, so Nerd Font icons in the starship
# prompt render as Tibetan letters. Pin the Nerd Font ranges to Meslo.
KITTY_CONF=/usr/share/osyx/config/.config/kitty/kitty.conf
[[ -f "$KITTY_CONF" ]] || { log "missing $KITTY_CONF"; exit 1; }
cat >>"$KITTY_CONF" <<'EOF'

# Added by the osyx image build: Nerd Font icons always from Meslo.
symbol_map U+E000-U+F8FF,U+F0000-U+FFFFD MesloLGS Nerd Font Mono
EOF

cp -a /usr/share/osyx/config/. /etc/skel/
rm -f /etc/skel/_install_ /etc/skel/README.md
/usr/libexec/osyx-user-setup --populate /etc/skel

# zsh as the default shell for new users.
sed -i 's|^SHELL=.*|SHELL=/usr/bin/zsh|' /etc/default/useradd

chmod 0755 /usr/libexec/osyx-session /usr/libexec/osyx-user-setup

systemctl enable sddm.service
systemctl set-default graphical.target
systemctl --global enable osyx-user-setup.service

# Leave nothing behind that bootc lint would complain about.
dnf5 clean all
rm -rf /var/log/dnf5.log* /var/lib/dnf /var/cache/ldconfig /run/dnf /run/sddm /tmp/* \
  2>/dev/null || true
