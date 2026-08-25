#!/usr/bin/env bash
# UbunChy-desktop-bootstrap.sh
#
# Reproduces, on a fresh Ubuntu/GNOME machine, the Omarchy-themed desktop
# built in the original session: GTK themes (Tokyo Night, Catppuccin, Rosé
# Pine), matching GNOME Shell extensions, and the ubunchy-theme-set / app-grid
# theme switcher that pulls all 22 official Omarchy (basecamp/omarchy) color
# themes on demand and applies them across your terminal, editor, Claude Code,
# VS Code, Obsidian, GNOME Terminal, wallpaper, and lock screen.
#
# Usage:
#   chmod +x UbunChy-desktop-bootstrap.sh
#   ./UbunChy-desktop-bootstrap.sh
#
# Safe to re-run: every step is idempotent (apt installs, theme
# downloads/builds, and generated files all overwrite cleanly).
#
# Requires: Ubuntu with GNOME Shell, sudo access, and a network connection.
# You will be prompted for your sudo password once, for package installs.

set -euo pipefail

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (it calls sudo itself where needed)."
command -v gnome-shell >/dev/null 2>&1 || warn "gnome-shell not found -- this script targets Ubuntu's GNOME desktop; some steps may not apply."

THEMES_DIR="$HOME/.themes"
FONTS_DIR="$HOME/.local/share/fonts"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$THEMES_DIR" "$FONTS_DIR" "$EXT_DIR" "$BIN_DIR" "$APPS_DIR"

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------

log "Installing required packages (sudo password may be requested)..."
sudo apt-get update
sudo apt-get install -y \
  gnome-tweaks gnome-shell-extension-manager \
  sassc gtk2-engines-murrine gnome-themes-extra \
  papirus-icon-theme \
  jq curl git zenity dconf-cli unzip fontconfig \
  nodejs npm python3-pip

# ---------------------------------------------------------------------------
# 2. GNOME Shell extensions: User Themes, Blur my Shell, Just Perfection
# ---------------------------------------------------------------------------

install_extension() {
  local uuid="$1" shell_version zip_url zip_file
  shell_version=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [[ -n $shell_version ]] || shell_version=46

  log "Installing GNOME Shell extension: $uuid"
  zip_url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_version}" \
    | jq -r '.download_url // empty')

  if [[ -z $zip_url ]]; then
    warn "Could not resolve a download for $uuid (shell version $shell_version) -- skipping."
    return 0
  fi

  zip_file=$(mktemp --suffix=.shell-extension.zip)
  curl -fsSL "https://extensions.gnome.org${zip_url}" -o "$zip_file" || { warn "Download failed for $uuid"; rm -f "$zip_file"; return 0; }
  gnome-extensions install --force "$zip_file" 2>/dev/null || warn "gnome-extensions install reported an issue for $uuid (often harmless before first login)."
  rm -f "$zip_file"

  # Compile schemas as a safety net in case gnome-extensions install didn't.
  if [[ -d $EXT_DIR/$uuid/schemas ]]; then
    glib-compile-schemas "$EXT_DIR/$uuid/schemas" 2>/dev/null || true
  fi
}

install_extension "user-theme@gnome-shell-extensions.gcampax.github.com"
install_extension "blur-my-shell@aunetx"
install_extension "just-perfection-desktop@just-perfection"

log "Enabling extensions (they activate fully after your next login on Wayland)..."
CURRENT_ENABLED=$(gsettings get org.gnome.shell enabled-extensions)
python3 - "$CURRENT_ENABLED" <<'PYEOF' | { read -r merged; gsettings set org.gnome.shell enabled-extensions "$merged"; }
import ast, sys
current = ast.literal_eval(sys.argv[1])
add = [
  "user-theme@gnome-shell-extensions.gcampax.github.com",
  "blur-my-shell@aunetx",
  "just-perfection-desktop@just-perfection",
]
print(current + [u for u in add if u not in current])
PYEOF

# ---------------------------------------------------------------------------
# 3. GTK themes: Tokyo Night, Catppuccin, Rosé Pine
# ---------------------------------------------------------------------------

build_gtk_theme() {
  local repo="$1" name="$2" build_dir
  log "Building GTK theme: $name (from $repo)..."
  build_dir=$(mktemp -d)
  if git clone --depth 1 -q "https://github.com/$repo.git" "$build_dir/src"; then
    ( cd "$build_dir/src/themes" && bash install.sh -d "$THEMES_DIR" -n "$name" -c light dark -s standard ) \
      || warn "$name build finished with warnings (this is expected -- Sass deprecation notices, not failures)."
  else
    warn "Could not clone $repo -- skipping $name."
  fi
  rm -rf "$build_dir"
}

install_catppuccin_gtk_theme() {
  log "Installing GTK theme: Catppuccin (prebuilt)..."
  local build_dir tag url
  build_dir=$(mktemp -d)
  tag=$(curl -fsSL "https://api.github.com/repos/Fausto-Korpsvart/Catppuccin-GTK-Theme/releases/latest" | jq -r '.tag_name // empty')
  if [[ -z $tag ]]; then
    warn "Could not find a Catppuccin-GTK-Theme release -- skipping."
    rm -rf "$build_dir"
    return 0
  fi
  for f in Catppuccin.tar.xz Catppuccin-Macchiato.tar.xz; do
    url="https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme/releases/download/${tag}/${f}"
    curl -fsSL -o "$build_dir/$f" "$url" && tar -xJf "$build_dir/$f" -C "$build_dir"
  done
  for d in "$build_dir"/Catppuccin-Dark "$build_dir"/Catppuccin-Light; do
    [[ -d $d ]] || continue
    rm -rf "${THEMES_DIR:?}/$(basename "$d")"
    mv "$d" "$THEMES_DIR/"
  done
  rm -rf "$build_dir"
}

# Note: the exact original build invocation for "Tokyonight-Dark-Storm" predates
# this script (lost to an earlier context compaction) -- this rebuilds it from
# the same upstream engine used for Rose Pine below (genuine Tokyo Night
# colors, default accent, dark variant only) and renames the output to match
# the name ubunchy-theme-set already expects. Functionally equivalent; not
# guaranteed to be byte-identical to whatever produced the original folder.
log "Building GTK theme: Tokyonight-Dark-Storm (from Fausto-Korpsvart/Tokyonight-GTK-Theme)..."
TN_BUILD_DIR=$(mktemp -d)
if git clone --depth 1 -q "https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme.git" "$TN_BUILD_DIR/src"; then
  ( cd "$TN_BUILD_DIR/src/themes" && bash install.sh -d "$THEMES_DIR" -n Tokyonight -c dark -s standard ) \
    || warn "Tokyonight build finished with warnings (expected -- Sass deprecation notices, not failures)."
  if [[ -d "$THEMES_DIR/Tokyonight-Dark" && ! -d "$THEMES_DIR/Tokyonight-Dark-Storm" ]]; then
    mv "$THEMES_DIR/Tokyonight-Dark" "$THEMES_DIR/Tokyonight-Dark-Storm"
    mv "$THEMES_DIR/Tokyonight-Dark-hdpi" "$THEMES_DIR/Tokyonight-Dark-Storm-hdpi" 2>/dev/null || true
    mv "$THEMES_DIR/Tokyonight-Dark-xhdpi" "$THEMES_DIR/Tokyonight-Dark-Storm-xhdpi" 2>/dev/null || true
  fi
else
  warn "Could not clone Tokyonight-GTK-Theme -- skipping."
fi
rm -rf "$TN_BUILD_DIR"

install_catppuccin_gtk_theme

build_gtk_theme "Fausto-Korpsvart/Rose-Pine-GTK-Theme" "Rosepine"

build_gtk_theme "Fausto-Korpsvart/Gruvbox-GTK-Theme" "Gruvbox"

log "Installing GTK theme: Nordic (prebuilt)..."
NORDIC_TMP=$(mktemp -d)
NORDIC_TAG=$(curl -fsSL "https://api.github.com/repos/EliverLara/Nordic/releases/latest" | jq -r '.tag_name // empty')
if [[ -n $NORDIC_TAG ]] && curl -fsSL -o "$NORDIC_TMP/Nordic.tar.xz" "https://github.com/EliverLara/Nordic/releases/download/${NORDIC_TAG}/Nordic.tar.xz"; then
  tar -xJf "$NORDIC_TMP/Nordic.tar.xz" -C "$NORDIC_TMP"
  rm -rf "$THEMES_DIR/Nordic"
  mv "$NORDIC_TMP/Nordic" "$THEMES_DIR/Nordic"
else
  warn "Could not fetch Nordic GTK theme -- skipping."
fi
rm -rf "$NORDIC_TMP"

build_gtk_theme "Fausto-Korpsvart/Everforest-GTK-Theme" "Everforest"
build_gtk_theme "Fausto-Korpsvart/Kanagawa-GKT-Theme" "Kanagawa"
build_gtk_theme "Fausto-Korpsvart/Matrix-GTK-Theme" "Matrix"
build_gtk_theme "Fausto-Korpsvart/Osaka-GTK-Theme" "Osaka"

log "Building GTK theme: Colloid (grey/black and orange/black variants)..."
COLLOID_TMP=$(mktemp -d)
if git clone --depth 1 -q "https://github.com/Fausto-Korpsvart/Colloid-gtk-theme.git" "$COLLOID_TMP/src"; then
  (
    cd "$COLLOID_TMP/src"
    bash install.sh -d "$THEMES_DIR" -n Colloid-Grey -t grey -c dark --tweaks black
    bash install.sh -d "$THEMES_DIR" -n Colloid-Orange -t orange -c dark --tweaks black
  ) || warn "Colloid build finished with warnings (expected -- Sass deprecation notices, not failures)."
  # install.sh appends the -t variant name again on top of -n, giving e.g.
  # Colloid-Grey-Grey-Dark -- flatten that back to the name we actually want.
  for suffix in "" "-hdpi" "-xhdpi"; do
    [[ -d "$THEMES_DIR/Colloid-Grey-Grey-Dark$suffix" ]] && mv "$THEMES_DIR/Colloid-Grey-Grey-Dark$suffix" "$THEMES_DIR/Colloid-Grey-Dark$suffix"
    [[ -d "$THEMES_DIR/Colloid-Orange-Orange-Dark$suffix" ]] && mv "$THEMES_DIR/Colloid-Orange-Orange-Dark$suffix" "$THEMES_DIR/Colloid-Orange-Dark$suffix"
  done
else
  warn "Could not clone Colloid-gtk-theme -- skipping."
fi
rm -rf "$COLLOID_TMP"

# ---------------------------------------------------------------------------
# 4. JetBrains Mono Nerd Font
# ---------------------------------------------------------------------------

if [[ ! -d "$FONTS_DIR/JetBrainsMono" ]]; then
  log "Installing JetBrains Mono Nerd Font..."
  FONT_TMP=$(mktemp -d)
  if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$FONT_TMP/JetBrainsMono.zip"; then
    mkdir -p "$FONTS_DIR/JetBrainsMono"
    unzip -qo "$FONT_TMP/JetBrainsMono.zip" -d "$FONTS_DIR/JetBrainsMono"
    fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 || true
  else
    warn "Could not download JetBrains Mono Nerd Font -- skipping."
  fi
  rm -rf "$FONT_TMP"
fi

# ---------------------------------------------------------------------------
# 4b. Chromium-family browser theming: make the policy dir user-writable so
#     UbunChy-theme-apply.sh can update the theme color without a sudo
#     prompt on every single theme switch. Only for browsers actually
#     installed.
# ---------------------------------------------------------------------------

for entry in "chromium:/etc/chromium/policies/managed" \
             "google-chrome:/etc/opt/chrome/policies/managed" \
             "msedge:/etc/opt/edge/policies/managed" \
             "brave:/etc/brave/policies/managed"; do
  IFS=: read -r cmd policy_dir <<<"$entry"
  if command -v "$cmd" >/dev/null 2>&1; then
    log "Enabling browser theming for $cmd..."
    sudo mkdir -p "$policy_dir"
    sudo chown "$USER" "$policy_dir"
  fi
done

# ---------------------------------------------------------------------------
# 4c. Keyboard shortcut: Super+Ctrl+Space opens the theme picker
# ---------------------------------------------------------------------------

log "Binding Super+Ctrl+Space to the theme picker..."
KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ubunchy-theme/"
KEY_BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH"
gsettings set "$KEY_BASE" name "UbunChy Theme Picker" 2>/dev/null || true
gsettings set "$KEY_BASE" command "$BIN_DIR/ubunchy-theme-set" 2>/dev/null || true
gsettings set "$KEY_BASE" binding "<Super><Control>space" 2>/dev/null || true
KB_CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")
KB_CURRENT="${KB_CURRENT#@as }"
python3 - "$KB_CURRENT" "$KEY_PATH" <<'PYEOF' | { read -r merged; gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$merged" 2>/dev/null || true; }
import ast, sys
try:
    current = ast.literal_eval(sys.argv[1])
except Exception:
    current = []
path = sys.argv[2]
if path not in current:
    current.append(path)
print(current)
PYEOF

# ---------------------------------------------------------------------------
# 4d. Super+Space -> app search (Omarchy-style launcher), dock hidden
# ---------------------------------------------------------------------------

log "Freeing Super+Space (default: switch keyboard layout) and binding it to the app search view..."
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']"
gsettings set org.gnome.shell.keybindings toggle-application-view "['<Super>a', '<Super>space']"

log "Hiding the Ubuntu Dock (Super+Space replaces it as the app launcher)..."
DOCK_CURRENT=$(gsettings get org.gnome.shell enabled-extensions)
DOCK_CURRENT="${DOCK_CURRENT#@as }"
python3 - "$DOCK_CURRENT" <<'PYEOF' | { read -r merged; gsettings set org.gnome.shell enabled-extensions "$merged" 2>/dev/null || true; }
import ast, sys
try:
    current = ast.literal_eval(sys.argv[1])
except Exception:
    current = []
current = [u for u in current if u != "ubuntu-dock@ubuntu.com"]
print(current)
PYEOF
# Belt-and-suspenders for an already-running session where the disable above
# won't be picked up until next login: this makes the (still-loaded) dock
# auto-hide immediately too, so it's out of the way right now either way.
# intellihide has to go too -- with it on, the dock only hides when a window
# physically overlaps it, so it stays put on an otherwise-empty desktop.
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0 2>/dev/null || true
gsettings set org.gnome.shell.extensions.dash-to-dock show-delay 0.3 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4e. Keyboard shortcut: Super+H opens UbunChy Help
# ---------------------------------------------------------------------------

log "Freeing Super+H (default: minimize window) and binding it to UbunChy Help..."
gsettings set org.gnome.desktop.wm.keybindings minimize "[]" 2>/dev/null || true

HELP_KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ubunchy-help/"
HELP_KEY_BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$HELP_KEY_PATH"
gsettings set "$HELP_KEY_BASE" name "UbunChy Help" 2>/dev/null || true
gsettings set "$HELP_KEY_BASE" command "$BIN_DIR/ubunchy-help" 2>/dev/null || true
gsettings set "$HELP_KEY_BASE" binding "<Super>h" 2>/dev/null || true
KB_CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")
KB_CURRENT="${KB_CURRENT#@as }"
python3 - "$KB_CURRENT" "$HELP_KEY_PATH" <<'PYEOF' | { read -r merged; gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$merged" 2>/dev/null || true; }
import ast, sys
try:
    current = ast.literal_eval(sys.argv[1])
except Exception:
    current = []
path = sys.argv[2]
if path not in current:
    current.append(path)
print(current)
PYEOF

# ---------------------------------------------------------------------------
# 4f. Keyboard shortcut: Super+T opens the default terminal
# ---------------------------------------------------------------------------

log "Binding Super+T to open your default terminal..."
TERM_KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ubunchy-terminal/"
TERM_KEY_BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$TERM_KEY_PATH"
gsettings set "$TERM_KEY_BASE" name "UbunChy Open Terminal" 2>/dev/null || true
gsettings set "$TERM_KEY_BASE" command "$BIN_DIR/ubunchy-open-terminal" 2>/dev/null || true
gsettings set "$TERM_KEY_BASE" binding "<Super>t" 2>/dev/null || true
KB_CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")
KB_CURRENT="${KB_CURRENT#@as }"
python3 - "$KB_CURRENT" "$TERM_KEY_PATH" <<'PYEOF' | { read -r merged; gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$merged" 2>/dev/null || true; }
import ast, sys
try:
    current = ast.literal_eval(sys.argv[1])
except Exception:
    current = []
path = sys.argv[2]
if path not in current:
    current.append(path)
print(current)
PYEOF

# ---------------------------------------------------------------------------
# 4g. Keyboard shortcut: Super+Ctrl+A opens the Agents launcher
# ---------------------------------------------------------------------------

log "Binding Super+Ctrl+A to the Agents launcher..."
AGENTS_KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ubunchy-agents/"
AGENTS_KEY_BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$AGENTS_KEY_PATH"
gsettings set "$AGENTS_KEY_BASE" name "UbunChy Agents" 2>/dev/null || true
gsettings set "$AGENTS_KEY_BASE" command "$BIN_DIR/ubunchy-agents" 2>/dev/null || true
gsettings set "$AGENTS_KEY_BASE" binding "<Super><Control>a" 2>/dev/null || true
KB_CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")
KB_CURRENT="${KB_CURRENT#@as }"
python3 - "$KB_CURRENT" "$AGENTS_KEY_PATH" <<'PYEOF' | { read -r merged; gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$merged" 2>/dev/null || true; }
import ast, sys
try:
    current = ast.literal_eval(sys.argv[1])
except Exception:
    current = []
path = sys.argv[2]
if path not in current:
    current.append(path)
print(current)
PYEOF

# ---------------------------------------------------------------------------
# 5. Install the UbunChy theme-switcher scripts, README, and app-grid launcher
# ---------------------------------------------------------------------------

log "Installing UbunChy-theme-apply.sh..."
cat > "$HOME/UbunChy-theme-apply.sh" <<'OMARCHY_APPLY_SCRIPT_EOF'
#!/usr/bin/env bash
# UbunChy-theme-apply.sh
#
# Fetches an official Omarchy (https://github.com/basecamp/omarchy) color
# scheme and applies it to whichever supported apps are actually installed
# on this machine: Alacritty, Kitty, Foot, Ghostty, btop, Helix, Neovim,
# VS Code / VS Code Insiders / VSCodium / Cursor, Claude Code (CLI), and
# Obsidian.
#
# Every file this script is about to modify is backed up first (see
# BACKUP_DIR below). The script only ever touches files it knows about by
# name; it never does a broad delete.
#
# Usage:
#   ./UbunChy-theme-apply.sh                 # interactive theme picker
#   ./UbunChy-theme-apply.sh "Tokyo Night"    # apply a specific theme
#   ./UbunChy-theme-apply.sh --list           # list available themes and exit
#
# The color-resolution and template-rendering logic below is a self-contained
# port of Omarchy's own bin/omarchy-theme-color and bin/omarchy-theme-set-templates
# (MIT licensed), adapted to run standalone (no Omarchy install required) and
# to target real dotfile locations instead of Omarchy's internal state dir.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

GITHUB_API="https://api.github.com/repos/basecamp/omarchy"
RAW_BASE="https://raw.githubusercontent.com/basecamp/omarchy/HEAD"

STATE_DIR="$HOME/.local/state/ubunchy-theme"
# CACHE_DIR is reassigned per-theme in main() once $theme is known, so a
# theme applied before can be re-applied with zero network calls. Templates
# are theme-independent (same 10 files for every theme) and cached once,
# shared across all themes, in TEMPLATES_DIR.
CACHE_DIR="$STATE_DIR/cache"
CURRENT_DIR="$STATE_DIR/current"
TEMPLATES_DIR="$STATE_DIR/cache/templates"
WALLPAPER_DIR="$HOME/Pictures/Omarchy"
CUSTOM_THEMES_DIR="$HOME/.config/ubunchy-theme/custom-themes"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.local/state/ubunchy-theme/backups/$TS"

TEMPLATE_NAMES=(alacritty.toml kitty.conf foot.ini ghostty.conf btop.theme helix.toml neovim.lua vscode-theme.json obsidian.css claude.json chromium.theme)

# GNOME Terminal window transparency, applied on every theme switch (a user
# preference, not something Omarchy's own colors.toml defines) so a fresh
# install already looks like this instead of needing it set by hand once.
GNOME_TERMINAL_TRANSPARENCY_PERCENT=7

# Known theme slugs as of this script's writing, used only if the live
# GitHub API listing can't be fetched (offline, rate-limited, no jq).
FALLBACK_THEMES=(catppuccin-latte catppuccin ethereal everforest flexoki-light gruvbox hackerman kanagawa last-horizon lumon lupine matte-black miasma nord osaka-jade retro-82 ristretto rose-pine solitude tokyo-night vantablack white)

THEMES=()
APPLIED=()
SKIPPED=()
NOTES=()

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
have_any() { local c; for c in "$@"; do have "$c" && return 0; done; return 1; }

normalize_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '-'
}

# Back up a file (or symlink) before we touch it, preserving its path
# relative to $HOME under $BACKUP_DIR. Safe to call on paths that don't
# exist yet (no-op).
backup_file() {
  local path="$1" rel dest
  [[ -e $path || -L $path ]] || return 0
  case "$path" in
    "$HOME"/*) rel="${path#"$HOME"/}" ;;
    *) rel="outside-home/$(basename "$path")" ;;
  esac
  dest="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -a "$path" "$dest"
  NOTES+=("backed up $path -> $dest")
}

# ---------------------------------------------------------------------------
# 1. Discover and pick a theme
# ---------------------------------------------------------------------------

fetch_theme_list() {
  local json=""
  if have jq && json=$(curl -fsSL "$GITHUB_API/contents/themes" 2>/dev/null); then
    mapfile -t THEMES < <(printf '%s' "$json" | jq -r '.[] | select(.type=="dir") | .name')
  fi
  if [[ ${#THEMES[@]} -eq 0 ]]; then
    warn "Could not list themes from the GitHub API (offline, rate-limited, or jq missing); using the built-in list instead."
    THEMES=("${FALLBACK_THEMES[@]}")
  fi
}

resolve_theme() {
  local requested="$1" slug t
  slug=$(normalize_slug "$requested")
  for t in "${THEMES[@]}"; do
    if [[ $(normalize_slug "$t") == "$slug" ]]; then
      printf '%s' "$t"
      return 0
    fi
  done
  if [[ -d $CUSTOM_THEMES_DIR ]]; then
    for t in "$CUSTOM_THEMES_DIR"/*/; do
      [[ -f ${t}colors.toml ]] || continue
      t=$(basename "$t")
      if [[ $(normalize_slug "$t") == "$slug" ]]; then
        printf '%s' "$t"
        return 0
      fi
    done
  fi
  return 1
}

# Derive a short theme name from a git repo URL the same way real Omarchy
# does: strip a leading "omarchy-" and a trailing "-theme", lowercase.
derive_theme_name_from_repo() {
  local url="$1" path name
  path="$url"
  [[ $path != *"://"* && $path == *:*/* ]] && path="${path#*:}"
  name=$(basename -- "$path" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')
  printf '%s' "$name"
}

install_custom_theme() {
  local url="$1" name dest
  [[ -n $url ]] || die "Usage: $0 install <git-repo-url>"
  if [[ $url == -* || $url =~ ^[A-Za-z0-9][A-Za-z0-9+.-]*:: ]]; then
    die "'$url' looks like a git option or transport helper, not a repository."
  fi
  name=$(derive_theme_name_from_repo "$url")
  [[ -n $name && $name != .* && $name != */* ]] || die "'$url' does not give a usable theme name."
  dest="$CUSTOM_THEMES_DIR/$name"

  mkdir -p "$CUSTOM_THEMES_DIR"
  rm -rf "$dest"
  log "Cloning $url -> $dest"
  git clone --depth 1 -- "$url" "$dest" || die "Failed to clone $url"
  [[ -f $dest/colors.toml ]] || die "$url does not have a colors.toml at its root -- not a usable Omarchy theme."

  log "Installed custom theme '$name'. Apply it with: ubunchy-theme-set $name"
}

pick_theme_interactively() {
  local i choice
  echo "Available Omarchy themes:" >&2
  for i in "${!THEMES[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "${THEMES[$i]}" >&2
  done
  while true; do
    read -rp "Pick a theme [1-${#THEMES[@]}]: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#THEMES[@]} )); then
      printf '%s' "${THEMES[$((choice - 1))]}"
      return 0
    fi
    echo "Invalid choice, try again." >&2
  done
}

# ---------------------------------------------------------------------------
# 2. Download the theme's colors.toml + optional extras, and the templates
# ---------------------------------------------------------------------------

fetch_theme_assets() {
  local theme="$1" custom_dir="$CUSTOM_THEMES_DIR/$1" refresh="${2:-}"
  mkdir -p "$CACHE_DIR" "$TEMPLATES_DIR"

  if [[ -f $custom_dir/colors.toml ]]; then
    # Local disk, always cheap -- just resync from the installed custom theme.
    log "Using locally installed custom theme '$theme'..."
    cp "$custom_dir/colors.toml" "$CACHE_DIR/colors.toml"
    [[ -f $custom_dir/neovim.lua ]] && cp "$custom_dir/neovim.lua" "$CACHE_DIR/neovim.lua" || rm -f "$CACHE_DIR/neovim.lua"
    [[ -f $custom_dir/vscode.json ]] && cp "$custom_dir/vscode.json" "$CACHE_DIR/vscode.json" || rm -f "$CACHE_DIR/vscode.json"
    rm -rf "$WALLPAPER_DIR/$theme"
    [[ -d $custom_dir/backgrounds ]] && cp -r "$custom_dir/backgrounds" "$WALLPAPER_DIR/$theme"
    true
  elif [[ -f $CACHE_DIR/colors.toml && -z $refresh ]]; then
    log "Using cached colors for '$theme' (already applied before)."
  else
    log "Downloading colors for '$theme'..."
    # All three are independent GET requests -- fire them together instead
    # of paying network latency three times over.
    curl -fsSL "$RAW_BASE/themes/$theme/colors.toml" -o "$CACHE_DIR/colors.toml" &
    local colors_pid=$!
    # Optional: a theme may ship its own hand-written Neovim colorscheme and/or
    # point VS Code at a real published extension. Best effort, ignore 404s.
    curl -fsSL "$RAW_BASE/themes/$theme/neovim.lua" -o "$CACHE_DIR/neovim.lua" 2>/dev/null &
    local neovim_pid=$!
    curl -fsSL "$RAW_BASE/themes/$theme/vscode.json" -o "$CACHE_DIR/vscode.json" 2>/dev/null &
    local vscode_pid=$!

    wait "$colors_pid" || die "Theme '$theme' has no colors.toml on GitHub -- can't continue."
    wait "$neovim_pid" || rm -f "$CACHE_DIR/neovim.lua"
    wait "$vscode_pid" || rm -f "$CACHE_DIR/vscode.json"
  fi

  # Templates are the same 10 files for every theme -- fetch once ever
  # (shared across all themes), in parallel rather than one at a time.
  local name missing=0
  for name in "${TEMPLATE_NAMES[@]}"; do
    [[ -s $TEMPLATES_DIR/$name.tpl ]] || missing=1
  done
  if (( missing )) || [[ -n $refresh ]]; then
    log "Downloading app templates (first run, or --refresh; shared by every theme after this)..."
    local pids=()
    for name in "${TEMPLATE_NAMES[@]}"; do
      curl -fsSL "$RAW_BASE/default/themed/$name.tpl" -o "$TEMPLATES_DIR/$name.tpl" &
      pids+=("$!")
    done
    local pid ok=1
    for pid in "${pids[@]}"; do
      wait "$pid" || ok=0
    done
    (( ok )) || die "Failed to download one or more app templates."
  fi
}

# ---------------------------------------------------------------------------
# 3. Palette resolution -- port of bin/omarchy-theme-color
# ---------------------------------------------------------------------------

declare -A THEME_COLORS

mix_color() {
  local start="${1#\#}" end="${2#\#}" amount="$3"
  awk -v start="$start" -v end="$end" -v amount="$amount" '
    function hex_value(c) { return index("0123456789abcdef", tolower(c)) - 1 }
    function pair(h, i) { return hex_value(substr(h, i, 1)) * 16 + hex_value(substr(h, i + 1, 1)) }
    BEGIN {
      if (amount ~ /%$/) { sub(/%$/, "", amount); amount = amount / 100 }
      else { amount += 0; if (amount > 1) amount = amount / 100 }
      if (amount < 0) amount = 0
      if (amount > 1) amount = 1
      sr = pair(start, 1); sg = pair(start, 3); sb = pair(start, 5)
      er = pair(end, 1);   eg = pair(end, 3);   eb = pair(end, 5)
      r = int(sr * (1 - amount) + er * amount + 0.5)
      g = int(sg * (1 - amount) + eg * amount + 0.5)
      b = int(sb * (1 - amount) + eb * amount + 0.5)
      printf "#%02x%02x%02x\n", r, g, b
    }'
}

alias_theme_color() {
  local key="$1" fallback="$2"
  [[ ${THEME_COLORS[$key]:-} ]] || THEME_COLORS[$key]="${THEME_COLORS[$fallback]:-}"
}

parse_colors_file() {
  local file="$1" key value
  [[ -f $file ]] || return 0
  while IFS='=' read -r key value; do
    key="${key//[\"\' ]/}"
    [[ $key && $key != \#* ]] || continue
    if [[ $value == *[\"\']* ]]; then
      value="${value#*[\"\']}"
      value="${value%%[\"\']*}"
    else
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
    fi
    [[ $key =~ ^[A-Za-z0-9_-]+$ ]] || continue
    [[ $value =~ ^[A-Za-z0-9\#\(\),._+/%\ -]*$ ]] || continue
    THEME_COLORS[$key]="$value"
  done <"$file"
}

resolve_theme_mode() {
  local bg_hex lum
  [[ ${THEME_COLORS[mode]:-} ]] || THEME_COLORS[mode]="${THEME_COLORS[theme_type]:-}"
  if [[ ${THEME_COLORS[mode]:-} ]]; then
    return 0
  fi
  if [[ -f $CACHE_DIR/light.mode ]]; then
    THEME_COLORS[mode]="light"
  elif [[ ${THEME_COLORS[background]:-} =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    bg_hex="${THEME_COLORS[background]#\#}"
    lum=$(( $(printf "%d" "0x${bg_hex:0:2}") + $(printf "%d" "0x${bg_hex:2:2}") + $(printf "%d" "0x${bg_hex:4:2}") ))
    (( lum > 382 )) && THEME_COLORS[mode]="light" || THEME_COLORS[mode]="dark"
  else
    THEME_COLORS[mode]="dark"
  fi
}

resolve_theme_colors() {
  local key
  declare -A legacy_palette_alias=(
    [background]=bg [dark_background]=dark_bg [darker_background]=darker_bg
    [lighter_background]=lighter_bg [foreground]=fg [dark_foreground]=dark_fg
    [light_foreground]=light_fg [bright_foreground]=bright_fg
  )
  for key in "${!legacy_palette_alias[@]}"; do
    alias_theme_color "$key" "${legacy_palette_alias[$key]}"
  done

  [[ ${THEME_COLORS[background]:-} ]] || THEME_COLORS[background]="${THEME_COLORS[color0]:-}"
  [[ ${THEME_COLORS[foreground]:-} ]] || THEME_COLORS[foreground]="${THEME_COLORS[color7]:-}"
  [[ ${THEME_COLORS[background]:-} ]] && THEME_COLORS[color0]="${THEME_COLORS[background]}"
  [[ ${THEME_COLORS[foreground]:-} ]] && THEME_COLORS[color7]="${THEME_COLORS[foreground]}"

  declare -A legacy_alias=(
    [red]=color1 [green]=color2 [yellow]=color3 [blue]=color4 [magenta]=color5 [cyan]=color6
    [bright_red]=color9 [bright_green]=color10 [bright_yellow]=color11 [bright_blue]=color12
    [bright_magenta]=color13 [bright_cyan]=color14
  )
  for key in "${!legacy_alias[@]}"; do
    alias_theme_color "$key" "${legacy_alias[$key]}"
  done
  alias_theme_color magenta purple
  alias_theme_color bright_magenta bright_purple

  [[ ${THEME_COLORS[light_foreground]:-} ]] || THEME_COLORS[light_foreground]="${THEME_COLORS[color7]:-${THEME_COLORS[foreground]:-}}"
  [[ ${THEME_COLORS[bright_foreground]:-} ]] || THEME_COLORS[bright_foreground]="${THEME_COLORS[color15]:-${THEME_COLORS[foreground]:-}}"
  THEME_COLORS[cursor]="${THEME_COLORS[bright_foreground]:-}"
  [[ ${THEME_COLORS[lighter_background]:-} ]] || THEME_COLORS[lighter_background]="${THEME_COLORS[color0]:-${THEME_COLORS[background]:-}}"
  [[ ${THEME_COLORS[dark_foreground]:-} ]] || THEME_COLORS[dark_foreground]="${THEME_COLORS[color8]:-${THEME_COLORS[foreground]:-}}"
  [[ ${THEME_COLORS[muted]:-} ]] || THEME_COLORS[muted]="${THEME_COLORS[color8]:-${THEME_COLORS[dark_foreground]:-}}"
  [[ ${THEME_COLORS[selection]:-} ]] || THEME_COLORS[selection]="${THEME_COLORS[selection_background]:-${THEME_COLORS[color8]:-${THEME_COLORS[color0]:-${THEME_COLORS[background]:-}}}}"
  [[ ${THEME_COLORS[selection_background]:-} ]] || THEME_COLORS[selection_background]="${THEME_COLORS[selection]:-}"
  [[ ${THEME_COLORS[selection_foreground]:-} ]] || THEME_COLORS[selection_foreground]="${THEME_COLORS[bright_foreground]:-}"
  [[ ${THEME_COLORS[orange]:-} ]] || THEME_COLORS[orange]="${THEME_COLORS[yellow]:-}"
  [[ ${THEME_COLORS[brown]:-} ]] || THEME_COLORS[brown]=$(mix_color "${THEME_COLORS[orange]:-#000000}" "#000000" 50%)

  [[ ${THEME_COLORS[dark_background]:-} ]] || THEME_COLORS[dark_background]=$(mix_color "${THEME_COLORS[background]:-#000000}" "#000000" 25%)
  [[ ${THEME_COLORS[darker_background]:-} ]] || THEME_COLORS[darker_background]=$(mix_color "${THEME_COLORS[background]:-#000000}" "#000000" 50%)
  [[ ${THEME_COLORS[bright_red]:-} ]] || THEME_COLORS[bright_red]=$(mix_color "${THEME_COLORS[red]:-#ff0000}" "#ffffff" 20%)
  [[ ${THEME_COLORS[bright_yellow]:-} ]] || THEME_COLORS[bright_yellow]=$(mix_color "${THEME_COLORS[yellow]:-#ffff00}" "#ffffff" 20%)
  [[ ${THEME_COLORS[bright_green]:-} ]] || THEME_COLORS[bright_green]=$(mix_color "${THEME_COLORS[green]:-#00ff00}" "#ffffff" 20%)
  [[ ${THEME_COLORS[bright_cyan]:-} ]] || THEME_COLORS[bright_cyan]=$(mix_color "${THEME_COLORS[cyan]:-#00ffff}" "#ffffff" 20%)
  [[ ${THEME_COLORS[bright_blue]:-} ]] || THEME_COLORS[bright_blue]=$(mix_color "${THEME_COLORS[blue]:-#0000ff}" "#ffffff" 20%)
  [[ ${THEME_COLORS[bright_magenta]:-} ]] || THEME_COLORS[bright_magenta]=$(mix_color "${THEME_COLORS[magenta]:-#ff00ff}" "#ffffff" 20%)
  alias_theme_color purple magenta
  alias_theme_color bright_purple bright_magenta

  declare -A ansi_alias=(
    [color0]=background [color1]=red [color2]=green [color3]=yellow [color4]=blue [color5]=magenta
    [color6]=cyan [color7]=foreground [color8]=muted [color9]=bright_red [color10]=bright_green
    [color11]=bright_yellow [color12]=bright_blue [color13]=bright_magenta [color14]=bright_cyan
    [color15]=bright_foreground
  )
  for key in "${!ansi_alias[@]}"; do
    alias_theme_color "$key" "${ansi_alias[$key]}"
  done

  for key in "${!legacy_palette_alias[@]}"; do
    [[ ${THEME_COLORS[$key]:-} ]] && THEME_COLORS["${legacy_palette_alias[$key]}"]="${THEME_COLORS[$key]}"
  done

  resolve_theme_mode
  THEME_COLORS[theme_type]="${THEME_COLORS[mode]}"
}

# ---------------------------------------------------------------------------
# 4. Template rendering -- port of bin/omarchy-theme-set-templates
#    (plain {{ key }}, {{ key_strip }}, {{ key_rgb }}, {{ mix a b amt }} only;
#    the gradient/shell functions are Hyprland-shell-specific and unused by
#    the app templates this script targets)
# ---------------------------------------------------------------------------

hex_to_rgb() {
  local hex="${1#\#}"
  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

add_template_value() {
  local key="$1" value="$2" rgb
  printf 's|{{ %s }}|%s|g\n' "$key" "$value" >>"$SED_SCRIPT"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}" >>"$SED_SCRIPT"
  if [[ $value =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    rgb=$(hex_to_rgb "$value")
    printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$rgb" >>"$SED_SCRIPT"
  fi
}

add_mix_value() {
  local token="$1" content fn start_key end_key amount start end value
  content="${token#\{\{}"; content="${content%\}\}}"
  read -r fn start_key end_key amount <<<"$content"
  start="${THEME_COLORS[$start_key]:-}"
  end="${THEME_COLORS[$end_key]:-}"
  [[ $start =~ ^#[0-9A-Fa-f]{6}$ && $end =~ ^#[0-9A-Fa-f]{6}$ ]] || return 0
  value=$(mix_color "$start" "$end" "$amount")
  case "$fn" in
    mix) ;;
    mix_strip) value="${value#\#}" ;;
    mix_rgb) value=$(hex_to_rgb "$value") ;;
    *) return ;;
  esac
  printf 's|%s|%s|g\n' "$token" "$value" >>"$SED_SCRIPT"
}

add_mix_values() {
  local tpl token
  local -A seen=()
  for tpl in "$TEMPLATES_DIR"/*.tpl; do
    while IFS= read -r token; do
      [[ -n ${seen[$token]:-} ]] && continue
      seen[$token]=1
      add_mix_value "$token"
    done < <(grep -hEo '\{\{[[:space:]]*mix(_strip|_rgb)?[[:space:]]+[A-Za-z0-9_]+[[:space:]]+[A-Za-z0-9_]+[[:space:]]+[0-9]+([.][0-9]+)?%?[[:space:]]*\}\}' "$tpl" 2>/dev/null || true)
  done
}

render_theme_templates() {
  local key tpl filename output_path
  SED_SCRIPT=$(mktemp)

  for key in "${!THEME_COLORS[@]}"; do
    add_template_value "$key" "${THEME_COLORS[$key]}"
  done
  add_mix_values

  mkdir -p "$CURRENT_DIR"
  for tpl in "$TEMPLATES_DIR"/*.tpl; do
    filename=$(basename "$tpl" .tpl)
    output_path="$CURRENT_DIR/$filename"
    sed -f "$SED_SCRIPT" "$tpl" >"$output_path"
  done
  rm -f "$SED_SCRIPT"

  # A theme-provided Neovim colorscheme is real Lua, not a template -- prefer
  # it verbatim over the generic fallback we just rendered.
  if [[ -s $CACHE_DIR/neovim.lua ]]; then
    cp "$CACHE_DIR/neovim.lua" "$CURRENT_DIR/neovim.lua"
  fi
}

# ---------------------------------------------------------------------------
# 5. Generic app-integration helpers
# ---------------------------------------------------------------------------

# Append a one-line include/import directive to $file, creating it if it
# doesn't exist yet. Idempotent (checks the exact line first). If $marker is
# non-empty and matches something already in the file, we back off and warn
# instead of risking a broken/duplicate config.
append_include_if_absent() {
  local file="$1" line="$2" marker="${3:-}"
  mkdir -p "$(dirname "$file")"
  if [[ ! -e $file ]]; then
    printf '%s\n' "$line" >"$file"
    APPLIED+=("created $file")
    return
  fi
  if grep -qF -- "$line" "$file"; then
    APPLIED+=("$file already includes the theme (unchanged)")
    return
  fi
  if [[ -n $marker ]] && grep -qE "$marker" "$file"; then
    warn "$file already customizes this; add manually: $line"
    SKIPPED+=("$file (already customized -- add manually)")
    return
  fi
  backup_file "$file"
  printf '\n%s\n' "$line" >>"$file"
  APPLIED+=("updated $file")
}

# Set a simple `key = "value"` line in an ini-ish file, replacing an
# existing one if present.
set_kv_line() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  if [[ ! -e $file ]]; then
    printf '%s = "%s"\n' "$key" "$value" >"$file"
    APPLIED+=("created $file")
    return
  fi
  backup_file "$file"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = \"${value}\"|" "$file"
  else
    printf '\n%s = "%s"\n' "$key" "$value" >>"$file"
  fi
  APPLIED+=("updated $file")
}

# Symlink $linkpath -> $target, backing up whatever was there first (unless
# it's already this exact symlink).
link_theme_file() {
  local target="$1" linkpath="$2"
  if [[ -L $linkpath && "$(readlink "$linkpath")" == "$target" ]]; then
    return 0
  fi
  backup_file "$linkpath"
  mkdir -p "$(dirname "$linkpath")"
  ln -snf "$target" "$linkpath"
}

# ---------------------------------------------------------------------------
# 6. Per-app integrations
# ---------------------------------------------------------------------------

apply_alacritty() {
  local cfg="$HOME/.config/alacritty/alacritty.toml"
  have_any alacritty || [[ -d $HOME/.config/alacritty ]] || { SKIPPED+=("Alacritty (not found)"); return; }
  append_include_if_absent "$cfg" \
    "[general]
import = [\"$CURRENT_DIR/alacritty.toml\"]" \
    '^\s*\[general\]|general\.import|^\s*import\s*='
}

apply_kitty() {
  local cfg="$HOME/.config/kitty/kitty.conf"
  have_any kitty || [[ -d $HOME/.config/kitty ]] || { SKIPPED+=("Kitty (not found)"); return; }
  append_include_if_absent "$cfg" "include $CURRENT_DIR/kitty.conf"
}

apply_foot() {
  local cfg="$HOME/.config/foot/foot.ini"
  have_any foot || [[ -d $HOME/.config/foot ]] || { SKIPPED+=("Foot (not found)"); return; }
  append_include_if_absent "$cfg" "include=$CURRENT_DIR/foot.ini"
}

apply_ghostty() {
  local cfg="$HOME/.config/ghostty/config"
  have_any ghostty || [[ -d $HOME/.config/ghostty ]] || { SKIPPED+=("Ghostty (not found)"); return; }
  append_include_if_absent "$cfg" "config-file = ?\"$CURRENT_DIR/ghostty.conf\""
}

apply_gnome_terminal() {
  have dconf || { SKIPPED+=("GNOME Terminal (dconf not found)"); return; }
  local uuid base i colors=()
  uuid=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
  [[ -n $uuid ]] || { SKIPPED+=("GNOME Terminal (not found)"); return; }
  base="/org/gnome/terminal/legacy/profiles:/:$uuid/"

  mkdir -p "$BACKUP_DIR/gnome-terminal"
  dconf dump "$base" >"$BACKUP_DIR/gnome-terminal/$uuid.dconf-backup" 2>/dev/null
  NOTES+=("backed up GNOME Terminal profile -> $BACKUP_DIR/gnome-terminal/$uuid.dconf-backup (restore with: dconf load '$base' < that file)")

  for i in $(seq 0 15); do
    colors+=("'${THEME_COLORS[color$i]}'")
  done

  dconf write "${base}use-theme-colors" "false"
  dconf write "${base}background-color" "'${THEME_COLORS[background]}'"
  dconf write "${base}foreground-color" "'${THEME_COLORS[foreground]}'"
  dconf write "${base}bold-color-same-as-fg" "true"
  dconf write "${base}cursor-colors-set" "true"
  dconf write "${base}cursor-background-color" "'${THEME_COLORS[bright_foreground]}'"
  dconf write "${base}cursor-foreground-color" "'${THEME_COLORS[background]}'"
  dconf write "${base}highlight-colors-set" "true"
  dconf write "${base}highlight-background-color" "'${THEME_COLORS[selection_background]}'"
  dconf write "${base}highlight-foreground-color" "'${THEME_COLORS[selection_foreground]}'"
  dconf write "${base}palette" "[$(IFS=,; echo "${colors[*]}")]"
  dconf write "${base}use-theme-transparency" "false"
  dconf write "${base}use-transparent-background" "true"
  dconf write "${base}background-transparency-percent" "$GNOME_TERMINAL_TRANSPARENCY_PERCENT"

  APPLIED+=("GNOME Terminal profile ($uuid) -> background ${THEME_COLORS[background]}, ${GNOME_TERMINAL_TRANSPARENCY_PERCENT}% transparent")
  NOTES+=("GNOME Terminal: open a new window/tab (existing open windows pick up the new colors automatically; no restart needed).")
}

apply_btop() {
  local cfg="$HOME/.config/btop/btop.conf" link="$HOME/.config/btop/themes/current.theme"
  have_any btop || [[ -d $HOME/.config/btop ]] || { SKIPPED+=("btop (not found)"); return; }
  link_theme_file "$CURRENT_DIR/btop.theme" "$link"
  set_kv_line "$cfg" color_theme current
  APPLIED+=("btop -> $link")
}

apply_helix() {
  local cfg="$HOME/.config/helix/config.toml" link="$HOME/.config/helix/themes/omarchy.toml"
  have_any hx helix || [[ -d $HOME/.config/helix ]] || { SKIPPED+=("Helix (not found)"); return; }
  link_theme_file "$CURRENT_DIR/helix.toml" "$link"
  set_kv_line "$cfg" theme omarchy
  APPLIED+=("Helix -> $link")
}

apply_neovim() {
  local dest="$HOME/.config/nvim/colors/omarchy.lua"
  have nvim || [[ -d $HOME/.config/nvim ]] || { SKIPPED+=("Neovim (not found)"); return; }
  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  cp "$CURRENT_DIR/neovim.lua" "$dest"
  APPLIED+=("Neovim colorscheme -> $dest")
  NOTES+=("Neovim: run ':colorscheme omarchy', or add vim.cmd.colorscheme('omarchy') to your init.lua to make it permanent.")
}

# VS Code / Insiders / VSCodium / Cursor share the same mechanism.
apply_vscode_editor() {
  local cmd="$1" settings="$2" ext_base="$3" label="$4"
  have "$cmd" || { SKIPPED+=("$label (not found)"); return; }
  have jq || { warn "jq not found; skipping $label theme activation"; SKIPPED+=("$label (jq missing)"); return; }

  local theme_name="" extension=""
  if [[ -f $CACHE_DIR/vscode.json ]]; then
    theme_name=$(jq -r '.name // empty' "$CACHE_DIR/vscode.json")
    extension=$(jq -r '.extension // empty' "$CACHE_DIR/vscode.json")
    if [[ -n $extension && $extension =~ ^[A-Za-z0-9._-]+$ ]]; then
      # `code --install-extension` has real CLI startup cost (250ms+) even
      # just to confirm something already installed -- check the extensions
      # directory on disk first, which is instant, and only shell out when
      # actually needed (i.e. once, ever, per extension).
      if ! find "$ext_base" -maxdepth 1 -iname "${extension}-*" -print -quit 2>/dev/null | grep -q .; then
        "$cmd" --install-extension "$extension" >/dev/null 2>&1 \
          || { warn "$label: couldn't install extension $extension, falling back to generated theme"; theme_name=""; }
      fi
    else
      theme_name=""
    fi
  fi

  if [[ -z $theme_name ]]; then
    local ext_dir="$ext_base/omarchy-theme"
    mkdir -p "$ext_dir/themes"
    cp "$CURRENT_DIR/vscode-theme.json" "$ext_dir/themes/omarchy-color-theme.json"
    local ui_theme="vs-dark"
    if [[ $(jq -r '.type // "dark"' "$CURRENT_DIR/vscode-theme.json") == "light" ]]; then
      ui_theme="vs"
    fi
    cat >"$ext_dir/package.json" <<EOF
{
  "name": "omarchy-theme",
  "displayName": "Omarchy",
  "description": "Omarchy color theme",
  "publisher": "local",
  "version": "1.0.0",
  "engines": { "vscode": "^1.70.0" },
  "categories": ["Themes"],
  "contributes": {
    "themes": [{ "label": "Omarchy", "uiTheme": "$ui_theme", "path": "./themes/omarchy-color-theme.json" }]
  }
}
EOF
    local extensions_file="$ext_base/extensions.json"
    [[ -f $extensions_file ]] || printf '[]\n' >"$extensions_file"
    backup_file "$extensions_file"
    local tmp; tmp=$(mktemp)
    jq --arg id "local.omarchy-theme" --arg version "1.0.0" --arg fs_path "$ext_dir" \
       --arg external "file://$ext_dir" --arg relative "omarchy-theme" \
       'map(select(.identifier.id != $id)) + [{
          identifier: { id: $id }, version: $version,
          location: { "$mid": 1, fsPath: $fs_path, external: $external, path: $fs_path, scheme: "file" },
          relativeLocation: $relative
        }]' "$extensions_file" >"$tmp" && mv "$tmp" "$extensions_file"
    theme_name="Omarchy"
  fi

  mkdir -p "$(dirname "$settings")"
  [[ -f $settings ]] || printf '{\n}\n' >"$settings"
  backup_file "$settings"
  local escaped=${theme_name//&/\\&}
  escaped=${escaped//|/\\|}
  if ! grep -q '"workbench.colorTheme"' "$settings"; then
    sed -i --follow-symlinks -E '0,/\{/{s/\{/{ "workbench.colorTheme": "",/}' "$settings"
  fi
  sed -i --follow-symlinks -E "s|(\"workbench.colorTheme\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1$escaped\2|" "$settings"
  APPLIED+=("$label -> \"$theme_name\" ($settings)")
}

apply_vscode_family() {
  apply_vscode_editor code "$HOME/.config/Code/User/settings.json" "$HOME/.vscode/extensions" "VS Code"
  apply_vscode_editor code-insiders "$HOME/.config/Code - Insiders/User/settings.json" "$HOME/.vscode-insiders/extensions" "VS Code Insiders"
  apply_vscode_editor codium "$HOME/.config/VSCodium/User/settings.json" "$HOME/.vscode-oss/extensions" "VSCodium"
  apply_vscode_editor cursor "$HOME/.config/Cursor/User/settings.json" "$HOME/.cursor/extensions" "Cursor"
}

apply_claude_code() {
  local cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [[ -d $cfg_dir ]] || { SKIPPED+=("Claude Code (not found)"); return; }
  local theme_dest="$cfg_dir/themes/omarchy.json" settings="$cfg_dir/settings.json"
  mkdir -p "$(dirname "$theme_dest")"
  backup_file "$theme_dest"
  cp "$CURRENT_DIR/claude.json" "$theme_dest"
  if have jq; then
    if [[ -f $settings ]]; then
      backup_file "$settings"
      local tmp; tmp=$(mktemp)
      jq '.theme = "custom:omarchy"' "$settings" >"$tmp" && mv "$tmp" "$settings"
    else
      printf '{\n  "theme": "custom:omarchy"\n}\n' >"$settings"
    fi
    APPLIED+=("Claude Code -> \"custom:omarchy\" ($settings)")
  else
    warn "jq not found; wrote $theme_dest but did not activate it in $settings"
    NOTES+=("Claude Code: set \"theme\": \"custom:omarchy\" in $settings to activate.")
  fi
}

fetch_theme_wallpapers() {
  local theme="$1" refresh="${2:-}" json dir
  dir="$WALLPAPER_DIR/$theme"

  if [[ -z $refresh ]] && find "$dir" -maxdepth 1 -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  have jq || { warn "jq not found; skipping wallpaper download"; return 0; }
  json=$(curl -fsSL "$GITHUB_API/contents/themes/$theme/backgrounds" 2>/dev/null) || return 0
  [[ -n $json ]] || return 0

  mkdir -p "$dir"

  local -a entries
  mapfile -t entries < <(printf '%s' "$json" | jq -r '.[] | select(.type=="file") | select(.name != "omarchy.webp") | [.name, .download_url] | @tsv' | sort)
  (( ${#entries[@]} > 0 )) || return 0

  # apply_wallpaper always picks the alphabetically-first image, so that's
  # the only one worth waiting for. The rest of the set downloads in a
  # detached background job -- ubunchy-wallpaper-next picks them up once
  # they land, but a theme switch doesn't sit around for images nobody is
  # looking at yet.
  local first_name first_url
  IFS=$'\t' read -r first_name first_url <<<"${entries[0]}"
  curl -fsSL "$first_url" -o "$dir/$first_name" 2>/dev/null || rm -f "$dir/$first_name"

  if (( ${#entries[@]} > 1 )); then
    (
      exec 9>&- 2>/dev/null || true
      local entry name url
      for entry in "${entries[@]:1}"; do
        IFS=$'\t' read -r name url <<<"$entry"
        [[ -f "$dir/$name" ]] && continue
        curl -fsSL "$url" -o "$dir/$name" 2>/dev/null || rm -f "$dir/$name"
      done
    ) </dev/null >/dev/null 2>&1 &
  fi
}

apply_wallpaper() {
  local theme="$1" dir pic
  dir="$WALLPAPER_DIR/$theme"
  [[ -d $dir ]] || { SKIPPED+=("Wallpaper (none downloaded for $theme)"); return; }

  pic=$(find "$dir" -maxdepth 1 -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort | head -1)
  [[ -n $pic ]] || { SKIPPED+=("Wallpaper (no image files in $dir)"); return; }

  have gsettings || { SKIPPED+=("Wallpaper (gsettings not available)"); return; }

  gsettings set org.gnome.desktop.background picture-uri "file://$pic" 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$pic" 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver picture-uri "file://$pic" 2>/dev/null || true
  ln -snf "$pic" "$STATE_DIR/current-wallpaper"
  APPLIED+=("Wallpaper -> $pic")
  if [[ $(find "$dir" -maxdepth 1 -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | wc -l) -gt 1 ]]; then
    NOTES+=("This theme has more than one wallpaper -- run 'ubunchy-wallpaper-next' to cycle to the next one.")
  fi
}

emit_osc() {
  local code="$1" key="$2"
  [[ -n ${THEME_COLORS[$key]:-} ]] || return 0
  printf '\033]%s;%s\007' "$code" "${THEME_COLORS[$key]}"
}

# Retints the terminal this script is actually running in, live, via OSC
# escape codes -- no new window needed. Only reaches the terminal that ran
# the command; other already-open windows still pick up the change on their
# next new tab/window (or their own theme-osc replay), since a process can't
# write escape codes into a different terminal's tty from here.
apply_terminal_osc() {
  [[ -t 1 ]] || { SKIPPED+=("Live terminal color reload (stdout isn't a terminal)"); return 0; }

  emit_osc 10 foreground
  emit_osc 11 background
  emit_osc 12 cursor
  emit_osc 17 selection_background
  emit_osc 19 selection_foreground

  local i
  for i in $(seq 0 15); do
    [[ -n ${THEME_COLORS[color$i]:-} ]] || continue
    printf '\033]4;%d;%s\007' "$i" "${THEME_COLORS[color$i]}"
  done

  APPLIED+=("Live-retinted this terminal window (OSC escape codes)")
}

# Chromium-family browsers only read their theme color from a policy file
# under /etc, which a normal user can't write to. Rather than sudo-prompt on
# every single theme switch, this only writes when the directory is already
# user-writable and otherwise leaves a one-time setup note.
apply_browser() {
  local rgb hex any=0
  [[ -f $CURRENT_DIR/chromium.theme ]] || { SKIPPED+=("Browser theming (no chromium.theme rendered)"); return 0; }
  rgb=$(<"$CURRENT_DIR/chromium.theme")
  [[ -n $rgb ]] || { SKIPPED+=("Browser theming (empty chromium.theme)"); return 0; }
  hex=$(printf '#%02x%02x%02x' ${rgb//,/ } 2>/dev/null) || { SKIPPED+=("Browser theming (couldn't parse color)"); return 0; }

  local browser policy_dir cmd process
  for browser in \
    "chromium:/etc/chromium/policies/managed:chromium" \
    "Google Chrome:/etc/opt/chrome/policies/managed:google-chrome" \
    "Microsoft Edge:/etc/opt/edge/policies/managed:msedge" \
    "Brave:/etc/brave/policies/managed:brave"; do
    IFS=: read -r browser policy_dir cmd <<<"$browser"
    process="$cmd"

    if [[ -d $policy_dir && -w $policy_dir ]]; then
      printf '{"BrowserThemeColor": "%s", "BrowserColorScheme": "device"}' "$hex" >"$policy_dir/color.json"
      any=1
      APPLIED+=("$browser theme color -> $hex")
      if have "$cmd" && pgrep -x "$process" >/dev/null 2>&1; then
        "$cmd" --refresh-platform-policy --no-startup-window &>/dev/null &
      fi
    elif [[ -d $policy_dir ]]; then
      NOTES+=("$browser: policy dir $policy_dir exists but isn't writable -- run once: sudo chown \"\$USER\" $policy_dir")
    elif have "$cmd"; then
      NOTES+=("$browser is installed but has no policy dir yet -- run once to enable theming: sudo mkdir -p $policy_dir && sudo chown \"\$USER\" $policy_dir")
    fi
  done

  (( any )) || SKIPPED+=("Browser theming (no Chromium-family browser policy dir writable yet -- see notes)")
}

apply_obsidian() {
  local obsidian_json="$HOME/.config/obsidian/obsidian.json"
  [[ -f $obsidian_json ]] || { SKIPPED+=("Obsidian (not found)"); return; }
  have jq || { warn "jq not found; skipping Obsidian"; SKIPPED+=("Obsidian (jq missing)"); return; }

  local vault_path any=0
  while IFS= read -r vault_path; do
    [[ -d "$vault_path/.obsidian" ]] || continue
    any=1
    local theme_dir="$vault_path/.obsidian/themes/Omarchy"
    mkdir -p "$theme_dir"
    if [[ ! -f $theme_dir/manifest.json ]]; then
      cat >"$theme_dir/manifest.json" <<'EOF'
{
  "name": "Omarchy",
  "version": "1.0.0",
  "minAppVersion": "0.16.0",
  "description": "Omarchy system theme colors",
  "author": "Omarchy",
  "authorUrl": "https://omarchy.org"
}
EOF
    fi
    backup_file "$theme_dir/theme.css"
    cp "$CURRENT_DIR/obsidian.css" "$theme_dir/theme.css"
    APPLIED+=("Obsidian vault \"$vault_path\" -> \"Omarchy\" theme installed")
  done < <(jq -r '.vaults | values[].path' "$obsidian_json" 2>/dev/null)

  if [[ $any -eq 1 ]]; then
    NOTES+=("Obsidian: open Settings > Appearance in each vault and select the \"Omarchy\" theme to activate it.")
  else
    SKIPPED+=("Obsidian (no initialized vaults found)")
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local arg="${1:-}" refresh=""

  if [[ $arg == "--refresh" ]]; then
    refresh=1
    shift || true
    arg="${1:-}"
  fi

  if [[ $arg == "-h" || $arg == "--help" ]]; then
    sed -n '2,20p' "$0"
    exit 0
  fi

  if [[ $arg == "install" ]]; then
    install_custom_theme "${2:-}"
    exit 0
  fi

  local theme
  if [[ -n $arg && $arg != "--list" ]]; then
    # Fast path: match against the known theme names without touching the
    # network at all. Only fall back to the live GitHub listing (needed for
    # --list, the interactive picker, or a theme newer than this script's
    # built-in list) when the fast match fails.
    THEMES=("${FALLBACK_THEMES[@]}")
    theme=$(resolve_theme "$arg") || {
      fetch_theme_list
      theme=$(resolve_theme "$arg") || die "Theme '$arg' not found. Run with --list to see available themes."
    }
  else
    fetch_theme_list
    if [[ $arg == "--list" ]]; then
      printf '%s\n' "${THEMES[@]}"
      if [[ -d $CUSTOM_THEMES_DIR ]]; then
        local c
        for c in "$CUSTOM_THEMES_DIR"/*/; do
          [[ -f ${c}colors.toml ]] || continue
          printf '%s (custom)\n' "$(basename "$c")"
        done
      fi
      exit 0
    fi
    theme=$(pick_theme_interactively)
  fi

  log "Applying Omarchy theme: $theme"
  CACHE_DIR="$STATE_DIR/cache/themes/$theme"
  mkdir -p "$BACKUP_DIR" "$CURRENT_DIR" "$CACHE_DIR"

  # Serialize the whole fetch+render+apply pipeline: TEMPLATES_DIR and
  # CURRENT_DIR are shared across all themes (not per-theme), so two
  # overlapping runs (e.g. the app-grid picker still open while another
  # invocation runs) would otherwise interleave writes and apply a mix of
  # two themes' colors.
  local lock_file="${XDG_RUNTIME_DIR:-/tmp}/omarchy-theme-apply.lock"
  exec 9>"$lock_file"
  flock 9

  fetch_theme_assets "$theme" "$refresh"
  fetch_theme_wallpapers "$theme" "$refresh"
  parse_colors_file "$CACHE_DIR/colors.toml"
  resolve_theme_colors
  render_theme_templates
  printf '%s\n' "$theme" >"$CURRENT_DIR/theme.name"

  apply_alacritty
  apply_kitty
  apply_foot
  apply_ghostty
  apply_gnome_terminal
  apply_btop
  apply_helix
  apply_neovim
  apply_vscode_family
  apply_claude_code
  apply_obsidian
  apply_browser
  apply_wallpaper "$theme"
  apply_terminal_osc

  echo
  log "Done. Theme '$theme' applied."
  echo
  echo "Applied:"
  local x
  for x in "${APPLIED[@]:-}"; do [[ -n $x ]] && printf '  - %s\n' "$x"; done
  echo
  echo "Skipped (not installed / not detected):"
  for x in "${SKIPPED[@]:-}"; do [[ -n $x ]] && printf '  - %s\n' "$x"; done
  if [[ ${#NOTES[@]} -gt 0 ]]; then
    echo
    echo "Notes:"
    for x in "${NOTES[@]}"; do printf '  - %s\n' "$x"; done
  fi
  echo
  echo "Backups of every file that was changed are in: $BACKUP_DIR"
  echo "(If a backup subdirectory is empty it means nothing existed there to back up.)"
  echo
  echo "Restart any running terminal emulators / apps for the new theme to take effect."
}

main "$@"
OMARCHY_APPLY_SCRIPT_EOF
chmod +x "$HOME/UbunChy-theme-apply.sh"

log "Installing ubunchy-theme-set..."
cat > "$BIN_DIR/ubunchy-theme-set" <<'OMARCHY_THEME_SET_EOF'
#!/usr/bin/env bash
# ubunchy-theme-set — unified UbunChy theme switcher for this desktop,
# applying Omarchy's own color themes.
#
# Applies terminal/editor/app colors (via ~/UbunChy-theme-apply.sh, which
# supports all 22 official Omarchy themes) and, for the themes that have a
# matching GTK theme installed in ~/.themes, the GTK app style + shell
# (top bar) + light/dark mode too.
#
# Usage:
#   ubunchy-theme-set                 # live carousel: slide, it applies as you go
#   ubunchy-theme-set "Rose Pine"      # apply a specific theme by name
#   ubunchy-theme-set --refresh NAME   # force a fresh re-download instead of the cache

set -euo pipefail

APPLY_SCRIPT="$HOME/UbunChy-theme-apply.sh"
USER_THEME_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
STATE_DIR="$HOME/.local/state/ubunchy-theme"
CURRENT_DIR="$STATE_DIR/current"

# Pseudo-theme: not a real Omarchy theme (no colors.toml upstream), so it
# never goes through UbunChy-theme-apply.sh -- selecting it instead reverts
# every gsetting/dconf key this project ever touches back to its real,
# compiled-in Ubuntu factory default (via `gsettings reset` / `dconf reset`,
# not hardcoded values), so it stays correct even if Ubuntu's own defaults
# ever change.
UBUNTU_THEME_ID="ubuntu"

# omarchy theme slug -> "gtk-theme-name:light|dark"
# Only themes listed here get a matching GTK/shell look; every theme still
# gets its terminal/editor colors applied regardless.
declare -A DESKTOP_MAP=(
  [tokyo-night]="Tokyonight-Dark-Storm:dark"
  [catppuccin]="Catppuccin-Dark:dark"
  [catppuccin-latte]="Catppuccin-Light:light"
  [rose-pine]="Rosepine-Dark:dark"
  [gruvbox]="Gruvbox-Dark:dark"
  [nord]="Nordic:dark"
  [everforest]="Everforest-Dark:dark"
  [kanagawa]="Kanagawa-Dark:dark"
  [hackerman]="Matrix-Dark:dark"
  [osaka-jade]="Osaka-Dark:dark"
  [vantablack]="Colloid-Grey-Dark:dark"
  [matte-black]="Colloid-Orange-Dark:dark"
  [white]="Adwaita:light"
)

OFFICIAL_THEMES=(catppuccin-latte catppuccin ethereal everforest flexoki-light gruvbox hackerman kanagawa last-horizon lumon lupine matte-black miasma nord osaka-jade retro-82 ristretto rose-pine solitude tokyo-night vantablack white)
CUSTOM_THEMES_DIR="$HOME/.config/ubunchy-theme/custom-themes"
PICKER_SCRIPT="$HOME/.local/bin/ubunchy-theme-picker"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

normalize_slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '-'; }

all_themes() {
  printf '%s\n' "${OFFICIAL_THEMES[@]}"
  if [[ -d $CUSTOM_THEMES_DIR ]]; then
    local c
    for c in "$CUSTOM_THEMES_DIR"/*/; do
      [[ -f ${c}colors.toml ]] || continue
      basename "$c"
    done
  fi
  printf '%s\n' "$UBUNTU_THEME_ID"
  return 0
}

# Reverts every gsetting/dconf key this project ever touches back to its real
# compiled-in Ubuntu factory default. Uses `gsettings reset` / `dconf reset`
# throughout (never hardcoded values) so it stays correct even across Ubuntu
# releases with different defaults -- confirmed by reading the actual
# compiled schema + /usr/share/glib-2.0/schemas/10_ubuntu*.gschema.override
# files rather than assuming. Deliberately scoped to desktop chrome (GTK/icon
# theme, shell theme, dock, keybindings, wallpaper, GNOME Terminal colors) --
# per-app config snippets (Kitty/Alacritty/Foot/Ghostty include lines, VS
# Code/Neovim/btop/Obsidian themes, browser policy) are left alone, since
# Ubuntu doesn't ship opinions about those apps to revert to; pick a real
# Omarchy theme again any time to re-theme them.
reset_to_ubuntu_defaults() {
  log "Reverting desktop to stock Ubuntu defaults..."

  gsettings reset org.gnome.desktop.interface gtk-theme
  gsettings reset org.gnome.desktop.interface icon-theme
  gsettings reset org.gnome.desktop.interface cursor-theme
  gsettings reset org.gnome.desktop.interface color-scheme

  if [[ -d $USER_THEME_SCHEMA_DIR ]]; then
    gsettings --schemadir "$USER_THEME_SCHEMA_DIR" reset org.gnome.shell.extensions.user-theme name 2>/dev/null || true
  fi

  # GTK4/libadwaita apps (Files, Text Editor, Console, ...) never had a
  # gtk-theme-driven default to "reset" to -- they just need our override
  # symlinks gone so they fall back to their own real default again.
  local gtk4_dest="$HOME/.config/gtk-4.0" name
  for name in assets gtk.css gtk-dark.css; do
    [[ -L "$gtk4_dest/$name" ]] && rm -f "$gtk4_dest/$name"
  done
  if command -v nautilus >/dev/null 2>&1 && pgrep -x nautilus >/dev/null 2>&1; then
    nautilus -q >/dev/null 2>&1 || true
  fi

  # Dock: back to pinned/always-visible, the actual Ubuntu default (verified
  # against /usr/share/glib-2.0/schemas/10_ubuntu-dock.gschema.override).
  gsettings reset org.gnome.shell.extensions.dash-to-dock dock-fixed
  gsettings reset org.gnome.shell.extensions.dash-to-dock intellihide
  gsettings reset org.gnome.shell.extensions.dash-to-dock intellihide-mode
  gsettings reset org.gnome.shell.extensions.dash-to-dock autohide
  gsettings reset org.gnome.shell.extensions.dash-to-dock hide-delay
  gsettings reset org.gnome.shell.extensions.dash-to-dock show-delay

  # Super+Space back to switching keyboard layout (its real default);
  # Super+A alone opens the app grid again instead of Super+Space too.
  gsettings reset org.gnome.desktop.wm.keybindings switch-input-source
  gsettings reset org.gnome.shell.keybindings toggle-application-view

  gsettings reset org.gnome.desktop.background picture-uri
  gsettings reset org.gnome.desktop.background picture-uri-dark
  gsettings reset org.gnome.desktop.background picture-options
  gsettings reset org.gnome.desktop.screensaver picture-uri 2>/dev/null || true

  reset_gnome_terminal_defaults

  mkdir -p "$CURRENT_DIR"
  printf '%s\n' "$UBUNTU_THEME_ID" >"$CURRENT_DIR/theme.name"

  log "Desktop reverted to stock Ubuntu (GTK/icons, dock, wallpaper, Super+Space, GNOME Terminal). Per-app configs (Kitty, VS Code, Neovim, ...) are untouched -- pick any Omarchy theme to re-theme those."
}

# Un-sets only the specific dconf keys UbunChy-theme-apply.sh's
# apply_gnome_terminal() writes, reverting each to the profile's own schema
# default (use-theme-colors=true, no transparency, etc.) -- not a blanket
# `dconf reset -f` on the whole profile, which would also wipe unrelated
# settings you may have (font, keybindings) that have nothing to do with theming.
reset_gnome_terminal_defaults() {
  command -v dconf >/dev/null 2>&1 || return 0
  local uuid base key
  uuid=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
  [[ -n $uuid ]] || return 0
  base="/org/gnome/terminal/legacy/profiles:/:$uuid/"
  for key in use-theme-colors background-color foreground-color \
    bold-color-same-as-fg cursor-colors-set cursor-background-color cursor-foreground-color \
    highlight-colors-set highlight-background-color highlight-foreground-color palette \
    use-theme-transparency use-transparent-background background-transparency-percent; do
    dconf reset "${base}${key}" 2>/dev/null || true
  done
}

native_picker_available() {
  [[ -x $PICKER_SCRIPT ]] \
    && python3 -c "import gi; gi.require_version('Gtk','3.0')" >/dev/null 2>&1 \
    && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]
}

# Live carousel: applies each theme as you slide, on its own, so main() has
# nothing further to do once it closes -- there's no "chosen theme" to
# return, the last thing on screen when you closed it is already applied.
run_native_picker() {
  local current=""
  [[ -f "$HOME/.local/state/ubunchy-theme/current/theme.name" ]] \
    && current=$(<"$HOME/.local/state/ubunchy-theme/current/theme.name")
  "$PICKER_SCRIPT" --current "$current" $(all_themes)
}

# Fallback for when the native carousel isn't available: select once, then
# main() applies that single choice the normal way.
pick_fallback_interactively() {
  if command -v zenity >/dev/null 2>&1 && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    local args=() t marker
    while IFS= read -r t; do
      marker=FALSE
      [[ -n ${DESKTOP_MAP[$t]:-} ]] && t="$t (desktop theme available)"
      args+=("$marker" "$t")
    done < <(all_themes)
    zenity --list --radiolist --title="Choose a theme" \
      --text="Pick a theme to apply across your desktop and apps" \
      --column="" --column="Theme" "${args[@]}" --width=420 --height=560 \
      | sed -E 's/ \(desktop theme available\)$//'
  else
    local -a themes
    mapfile -t themes < <(all_themes)
    local i
    for i in "${!themes[@]}"; do
      printf '  %2d) %s%s\n' "$((i + 1))" "${themes[$i]}" \
        "$([[ -n ${DESKTOP_MAP[${themes[$i]}]:-} ]] && echo ' (desktop theme available)')" >&2
    done
    read -rp "Pick a theme [1-${#themes[@]}]: " choice
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#themes[@]} )) && printf '%s' "${themes[$((choice - 1))]}"
  fi
}

# Restores UbunChy's own desktop behavior (dock hidden, Super+Space as the
# app-grid launcher) -- the opposite of what reset_to_ubuntu_defaults() sets.
# This has to be reasserted on every real-theme apply, not just done once at
# install time, since selecting the "ubuntu" pseudo-theme flips these keys
# back to stock and nothing else would ever flip them forward again.
apply_ubunchy_desktop_behavior() {
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']" 2>/dev/null || true
  gsettings set org.gnome.shell.keybindings toggle-application-view "['<Super>a', '<Super>space']" 2>/dev/null || true

  gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock autohide true 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock show-delay 0.3 2>/dev/null || true
}

set_desktop_theme() {
  local slug="$1" entry gtk mode
  entry="${DESKTOP_MAP[$slug]:-}"
  if [[ -z $entry ]]; then
    warn "No matching GTK/shell desktop theme installed for '$slug' yet -- GTK/icons left as-is (terminal/app colors were still applied)."
    return
  fi
  gtk="${entry%%:*}"
  mode="${entry##*:}"
  gsettings set org.gnome.desktop.interface gtk-theme "$gtk"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-$mode"
  if [[ -d $USER_THEME_SCHEMA_DIR ]]; then
    gsettings --schemadir "$USER_THEME_SCHEMA_DIR" set org.gnome.shell.extensions.user-theme name "$gtk" 2>/dev/null \
      || warn "Couldn't set the shell theme (User Themes extension not active?)."
  fi
  link_libadwaita_theme "$gtk"
  log "Desktop (GTK app style + shell) theme set to $gtk ($mode)"
}

# GTK4/libadwaita apps (Nautilus/Files, Text Editor, Console, ...) ignore the
# gtk-theme gsetting entirely -- it's a GTK3-only mechanism. They only ever
# read ~/.config/gtk-4.0/gtk.css (and gtk-dark.css), which is why Files kept
# showing the default look even after everything else re-themed. Each GTK
# theme here ships its own gtk-4.0/{assets,gtk.css,gtk-dark.css}; this links
# them in, same as the installer's own --libadwaita flag would have.
link_libadwaita_theme() {
  local gtk="$1" src="$HOME/.themes/$gtk/gtk-4.0" dest="$HOME/.config/gtk-4.0"
  mkdir -p "$dest"
  # Not every GTK theme ships the same set of gtk-4.0 files (Nordic, from a
  # different upstream than the others, has no assets/ dir at all), and a
  # plain system theme like Adwaita has no gtk-4.0 override at all (GTK4
  # apps just use their real default, which is correct) -- either way, a
  # name this theme doesn't provide must be actively removed here, not just
  # skipped, or it silently keeps pointing at whatever theme set it last.
  local name
  for name in assets gtk.css gtk-dark.css; do
    if [[ ! -d $src || ! -e $src/$name ]]; then
      [[ -L $dest/$name ]] && rm -f "$dest/$name"
      continue
    fi
    if [[ -e $dest/$name && ! -L $dest/$name ]]; then
      mv "$dest/$name" "$dest/$name.pre-ubunchy-backup"
    fi
    ln -snf "$src/$name" "$dest/$name"
  done

  # GTK4 apps read this CSS exactly once, at process startup -- they never
  # notice the symlink target changing underneath them. Nautilus in
  # particular keeps a persistent background service alive between windows
  # (for fast subsequent launches), so without this, Files silently keeps
  # showing whatever theme was active when that service last started,
  # sometimes many theme switches ago. Quitting it is safe (no unsaved
  # state); GNOME relaunches it fresh, picking up the new CSS, the next
  # time Files is opened.
  if command -v nautilus >/dev/null 2>&1 && pgrep -x nautilus >/dev/null 2>&1; then
    nautilus -q >/dev/null 2>&1 || true
  fi
}

main() {
  local requested="${1:-}" slug="" found=0 t refresh=""

  if [[ $requested == "install" ]]; then
    exec bash "$APPLY_SCRIPT" install "${2:-}"
  fi

  if [[ $requested == "--list" ]]; then
    all_themes
    exit 0
  fi

  if [[ $requested == "--refresh" ]]; then
    refresh="--refresh"
    shift || true
    requested="${1:-}"
  fi

  if [[ -z $requested ]]; then
    if native_picker_available; then
      run_native_picker
      exit 0
    fi
    requested=$(pick_fallback_interactively)
  fi
  [[ -n $requested ]] || { warn "No theme chosen."; exit 1; }

  slug=$(normalize_slug "$requested")
  while IFS= read -r t; do
    if [[ $(normalize_slug "$t") == "$slug" ]]; then
      slug="$t"
      found=1
      break
    fi
  done < <(all_themes)
  (( found )) || { warn "Unknown theme '$requested'. Run with --list to see available themes."; exit 1; }

  if [[ $slug == "$UBUNTU_THEME_ID" ]]; then
    reset_to_ubuntu_defaults
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "UbunChy" "Reverted to stock Ubuntu" 2>/dev/null || true
    fi
    return
  fi

  log "Applying theme: $slug"
  bash "$APPLY_SCRIPT" ${refresh:+"$refresh"} "$slug"
  set_desktop_theme "$slug"
  apply_ubunchy_desktop_behavior

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "UbunChy theme" "Applied: $slug" 2>/dev/null || true
  fi
}

main "$@"
OMARCHY_THEME_SET_EOF
chmod +x "$BIN_DIR/ubunchy-theme-set"

log "Installing ubunchy-theme-picker (layered card-stack carousel)..."
cat > "$BIN_DIR/ubunchy-theme-picker" <<'OMARCHY_PICKER_SCRIPT_EOF'
#!/usr/bin/env python3
"""UbunChy theme carousel -- live, borderless, transparent theme picker.

Replicates Omarchy's own theme switcher: a fanned stack of theme preview
cards receding to either side of the selected one, which sits in front with
a bright border. Slide with the arrow keys, scroll wheel, or by clicking any
card in the stack; each theme applies automatically (debounced) as you land
on it -- no window chrome, no buttons, no Apply.

Usage:
  ubunchy-theme-picker [--current NAME] THEME1 THEME2 ...
"""
import os
import subprocess
import sys
import threading
import urllib.request

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gtk, GLib, Gdk  # noqa: E402

RAW_BASE = "https://raw.githubusercontent.com/basecamp/omarchy/HEAD"
CACHE_DIR = os.path.expanduser("~/.cache/ubunchy-theme/previews")
WALLPAPER_DIR = os.path.expanduser("~/Pictures/Omarchy")
THEME_SET = os.path.expanduser("~/.local/bin/ubunchy-theme-set")
APPLY_DEBOUNCE_MS = 300

# "ubuntu" is a pseudo-theme (revert to stock Ubuntu) -- it has no colors.toml
# and nothing under themes/ubuntu/ upstream, so it needs its own preview
# source: the actual wallpaper Ubuntu ships as its own default.
UBUNTU_THEME_ID = "ubuntu"
UBUNTU_PREVIEW_CANDIDATES = (
    "/usr/share/backgrounds/warty-final-ubuntu.png",
    "/usr/share/backgrounds/ubuntu-wallpaper-d.png",
)

# Card stack geometry: CARD_ASPECT matches every real Omarchy preview.png
# (16:9), so sizes are fully known up front -- no waiting on image loads to
# lay things out. Actual pixel sizes are computed at runtime as a fraction of
# the primary monitor (see Carousel._compute_geometry), so this scales
# sensibly across different screen sizes.
CARD_ASPECT = 16 / 9
LEVELS = 3                  # cards visible on each side of the selection
SCALE_STEP = 0.18           # width shrink per level away from center
MIN_OPACITY = 0.12
H_STEP_FRAC = 0.38          # horizontal offset per level, as a fraction of the center card's width
CENTER_WIDTH_FRAC = 0.40    # center card width, as a fraction of monitor width
VIEWPORT_WIDTH_FRAC = 0.90  # visible stage width (clips the fanned-out cards), as a fraction of monitor width

CSS = b"""
window.ubunchy-carousel, window.ubunchy-carousel * {
    background-color: transparent;
    background-image: none;
}
label.ubunchy-name {
    color: #ffffff;
    font-size: 22px;
    font-weight: bold;
    text-shadow: 1px 1px 4px rgba(0, 0, 0, 0.9), 0 0 12px rgba(0, 0, 0, 0.6);
}
label.ubunchy-name.applying {
    color: #cccccc;
}
frame.ubunchy-card {
    border: 1px solid rgba(255, 255, 255, 0.35);
    background: transparent;
}
frame.ubunchy-card.current {
    border: 3px solid #6fc9ff;
    box-shadow: 0 0 24px rgba(111, 201, 255, 0.55);
}
frame.ubunchy-card > border {
    border: none;
}
"""


def fetch_preview(theme: str) -> str | None:
    """Local image path for this theme's preview, downloading and caching on
    first use. Falls back to a locally downloaded wallpaper for custom
    themes. Network I/O -- call off the GTK main thread."""
    if theme == UBUNTU_THEME_ID:
        for path in UBUNTU_PREVIEW_CANDIDATES:
            if os.path.isfile(path):
                return path
        return None

    os.makedirs(CACHE_DIR, exist_ok=True)
    for ext in ("png", "jpg", "jpeg", "webp"):
        cached = os.path.join(CACHE_DIR, f"{theme}.{ext}")
        if os.path.isfile(cached):
            return cached

    for ext in ("png", "jpg", "webp"):
        url = f"{RAW_BASE}/themes/{theme}/preview.{ext}"
        dest = os.path.join(CACHE_DIR, f"{theme}.{ext}")
        try:
            urllib.request.urlretrieve(url, dest)
            if os.path.getsize(dest) > 0:
                return dest
            os.remove(dest)
        except Exception:
            if os.path.exists(dest):
                os.remove(dest)

    wp_dir = os.path.join(WALLPAPER_DIR, theme)
    if os.path.isdir(wp_dir):
        for name in sorted(os.listdir(wp_dir)):
            if name.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                return os.path.join(wp_dir, name)

    return None


def load_pixbuf(path: str | None, width: int, height: int) -> GdkPixbuf.Pixbuf | None:
    if not path:
        return None
    try:
        return GdkPixbuf.Pixbuf.new_from_file_at_scale(path, width, height, False)
    except Exception:
        return None


def display_name(theme: str) -> str:
    return " ".join(w.capitalize() for w in theme.replace("_", "-").split("-"))


class Card:
    """One card in the stack: a bordered frame around an image, absolutely
    positioned in the stage's Gtk.Fixed."""

    def __init__(self, fixed: Gtk.Fixed, level: int, on_click, geo: dict):
        self.level = level
        self.width = max(40, int(geo["base_width"] * (1 - abs(level) * SCALE_STEP)))
        self.height = int(self.width / CARD_ASPECT)

        self.image = Gtk.Image()
        self.frame = Gtk.Frame()
        self.frame.set_shadow_type(Gtk.ShadowType.NONE)
        self.frame.get_style_context().add_class("ubunchy-card")
        self.frame.add(self.image)

        self.event_box = Gtk.EventBox()
        self.event_box.add(self.frame)
        self.event_box.connect("button-press-event", lambda *_: on_click(level))
        self.event_box.set_size_request(self.width, self.height)

        x = geo["stage_width"] // 2 - self.width // 2 + int(level * geo["base_width"] * H_STEP_FRAC)
        y = geo["stage_height"] // 2 - self.height // 2
        fixed.put(self.event_box, x, y)

        opacity = 1.0 if level == 0 else max(MIN_OPACITY, 1.0 - abs(level) * 0.32)
        self.event_box.set_opacity(opacity)
        if level == 0:
            self.frame.get_style_context().add_class("current")

    def set_pixbuf(self, pixbuf: GdkPixbuf.Pixbuf | None):
        if pixbuf is not None:
            self.image.set_from_pixbuf(pixbuf)


class Carousel(Gtk.Window):
    def __init__(self, themes: list[str], current: str | None):
        super().__init__(title="UbunChy")
        self.themes = themes
        self.index = themes.index(current) if current in themes else 0
        self.apply_proc: subprocess.Popen | None = None
        self.debounce_id: int | None = None
        self.load_generation = 0
        self.centered_once = False
        self.center_settle_id: int | None = None
        self.geo = self._compute_geometry()

        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self._make_transparent()

        self.connect("destroy", self.on_destroy)
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-out-event", lambda *_: self.close())
        self.connect("size-allocate", self.on_size_allocate)

        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        outer.set_border_width(24)
        self.add(outer)

        # The stack of cards is built much wider than what's actually shown
        # (see _compute_geometry): a ScrolledWindow with scrolling/scrollbars
        # disabled is used purely as a fixed-size clipping viewport, the same
        # way Omarchy's own switcher lets the fanned-out cards run off the
        # edge of the screen instead of shrinking everything to fit.
        self.scrolled = Gtk.ScrolledWindow()
        # EXTERNAL (not NEVER) is what actually makes GTK honor
        # min/max-content as a hard cap instead of growing to fit the
        # (much wider) Fixed inside -- and, conveniently, it also means no
        # scrollbar is ever drawn, since it signals "scrolling is handled
        # some other way" (here: not at all, the view is static).
        self.scrolled.set_policy(Gtk.PolicyType.EXTERNAL, Gtk.PolicyType.EXTERNAL)
        self.scrolled.set_min_content_width(self.geo["viewport_width"])
        self.scrolled.set_min_content_height(self.geo["viewport_height"])
        self.scrolled.set_max_content_width(self.geo["viewport_width"])
        self.scrolled.set_max_content_height(self.geo["viewport_height"])
        self.scrolled.set_can_focus(False)
        self.scrolled.connect("scroll-event", self.on_scroll)
        outer.pack_start(self.scrolled, True, True, 0)

        self.fixed = Gtk.Fixed()
        self.fixed.set_size_request(self.geo["stage_width"], self.geo["stage_height"])
        self.scrolled.add(self.fixed)

        self.name_label = Gtk.Label()
        self.name_label.get_style_context().add_class("ubunchy-name")
        outer.pack_start(self.name_label, False, False, 0)

        # Gtk.Fixed stacks later .put() calls on top of earlier ones, so
        # cards are built farthest-from-center first and the selected one
        # last, putting it visually in front of the whole fanned stack.
        self.cards: dict[int, Card] = {}
        build_order = sorted(range(-LEVELS, LEVELS + 1), key=lambda lv: -abs(lv))
        for level in build_order:
            self.cards[level] = Card(self.fixed, level, self.on_card_clicked, self.geo)

        self.show_index(self.index, apply_it=False)

    @staticmethod
    def _compute_geometry() -> dict:
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor() or display.get_monitor(0)
        mon_geo = monitor.get_geometry() if monitor is not None else None
        mon_width = mon_geo.width if mon_geo is not None else 1920
        mon_height = mon_geo.height if mon_geo is not None else 1080

        base_width = int(mon_width * CENTER_WIDTH_FRAC)
        viewport_width = min(int(mon_width * VIEWPORT_WIDTH_FRAC), mon_width - 80)
        stage_width = int(base_width + 2 * LEVELS * base_width * H_STEP_FRAC + base_width)
        card_height = int(base_width / CARD_ASPECT)
        stage_height = card_height + 20
        viewport_height = min(stage_height, mon_height - 160)

        return {
            "base_width": base_width,
            "stage_width": stage_width,
            "stage_height": stage_height,
            "viewport_width": viewport_width,
            "viewport_height": viewport_height,
        }

    def _make_transparent(self):
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)
        self.get_style_context().add_class("ubunchy-carousel")

    def on_size_allocate(self, _widget, _allocation):
        if self.centered_once:
            return
        if self.center_settle_id is not None:
            GLib.source_remove(self.center_settle_id)
        self.center_settle_id = GLib.timeout_add(120, self._finish_centering)

    def _finish_centering(self):
        self.center_settle_id = None
        self.centered_once = True

        # Center the clipping viewport on the middle of the stage, where the
        # selected card always sits. The adjustment's valid range only
        # becomes meaningful once the ScrolledWindow has actually been
        # allocated a size, hence doing this here rather than at construction
        # time (doing it too early just clamps to 0 and silently no-ops).
        hadj = self.scrolled.get_hadjustment()
        vadj = self.scrolled.get_vadjustment()
        hadj.set_value((self.geo["stage_width"] - self.geo["viewport_width"]) / 2)
        vadj.set_value((self.geo["stage_height"] - self.geo["viewport_height"]) / 2)

        display = self.get_display()
        monitor = display.get_primary_monitor() or display.get_monitor(0)
        if monitor is None:
            return False
        geo = monitor.get_geometry()
        width, height = self.get_size()
        x = geo.x + (geo.width - width) // 2
        y = geo.y + (geo.height - height) // 2
        self.move(x, y)
        return False

    # -- navigation --------------------------------------------------

    def step(self, delta: int):
        self.show_index((self.index + delta) % len(self.themes))

    def on_card_clicked(self, level: int):
        if level != 0:
            self.step(level)

    def on_scroll(self, _widget, event):
        if event.direction == Gdk.ScrollDirection.UP:
            self.step(-1)
        elif event.direction == Gdk.ScrollDirection.DOWN:
            self.step(1)
        return True  # stop the ScrolledWindow's own default pan-on-scroll

    def on_key_press(self, _widget, event):
        if event.keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self.step(-1)
        elif event.keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self.step(1)
        elif event.keyval == Gdk.KEY_Escape:
            self.close()

    # -- display + live apply -----------------------------------------

    def show_index(self, index: int, apply_it: bool = True):
        self.index = index
        theme = self.themes[index]

        self.name_label.set_text(display_name(theme))
        ctx = self.name_label.get_style_context()
        if apply_it:
            ctx.add_class("applying")
        else:
            ctx.remove_class("applying")

        self.load_generation += 1
        generation = self.load_generation
        n = len(self.themes)
        level_themes = {level: self.themes[(index + level) % n] for level in self.cards}
        threading.Thread(
            target=self._load_images_bg, args=(level_themes, generation), daemon=True
        ).start()

        if apply_it:
            if self.debounce_id is not None:
                GLib.source_remove(self.debounce_id)
            self.debounce_id = GLib.timeout_add(APPLY_DEBOUNCE_MS, self._commit_apply, theme)

    def _load_images_bg(self, level_themes: dict, generation: int):
        pixbufs = {}
        for level, theme in level_themes.items():
            card = self.cards[level]
            pixbufs[level] = load_pixbuf(fetch_preview(theme), card.width, card.height)
        GLib.idle_add(self._apply_pixbufs, pixbufs, generation)

    def _apply_pixbufs(self, pixbufs: dict, generation: int):
        if generation != self.load_generation:
            return False  # superseded by a newer navigation
        for level, pixbuf in pixbufs.items():
            self.cards[level].set_pixbuf(pixbuf)
        return False

    def _commit_apply(self, theme: str):
        self.debounce_id = None
        if self.apply_proc is not None and self.apply_proc.poll() is None:
            self.apply_proc.terminate()
        self.apply_proc = subprocess.Popen(
            [THEME_SET, theme],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        threading.Thread(target=self._watch_apply, args=(self.apply_proc,), daemon=True).start()
        return False

    def _watch_apply(self, proc: subprocess.Popen):
        proc.wait()
        GLib.idle_add(self._apply_done, proc)

    def _apply_done(self, proc: subprocess.Popen):
        if proc is self.apply_proc:
            self.name_label.get_style_context().remove_class("applying")
        return False

    def on_destroy(self, *_args):
        # Whatever's on screen when the window closes should actually be
        # committed, even if you closed it before the debounce fired.
        if self.debounce_id is not None:
            GLib.source_remove(self.debounce_id)
            self._commit_apply(self.themes[self.index])
        Gtk.main_quit()


def main():
    args = sys.argv[1:]
    current = None
    if args[:1] == ["--current"]:
        current = args[1] if len(args) > 1 else None
        args = args[2:]

    themes = args
    if not themes:
        print("Usage: ubunchy-theme-picker [--current NAME] THEME1 THEME2 ...", file=sys.stderr)
        sys.exit(2)

    win = Carousel(themes, current)
    win.show_all()
    Gtk.main()
    sys.exit(0)


if __name__ == "__main__":
    main()
OMARCHY_PICKER_SCRIPT_EOF
chmod +x "$BIN_DIR/ubunchy-theme-picker"

log "Installing ubunchy-wallpaper-next..."
cat > "$BIN_DIR/ubunchy-wallpaper-next" <<'OMARCHY_WALLPAPER_NEXT_EOF'
#!/usr/bin/env bash
# ubunchy-wallpaper-next -- cycle to the next wallpaper in the current
# Omarchy theme's set (wraps around). Mirrors bin/omarchy-theme-bg-next in
# the real basecamp/omarchy repo.

set -euo pipefail

STATE_DIR="$HOME/.local/state/ubunchy-theme"
WALLPAPER_DIR="$HOME/Pictures/Omarchy"
CURRENT_LINK="$STATE_DIR/current-wallpaper"
THEME_NAME_FILE="$STATE_DIR/current/theme.name"

[[ -f $THEME_NAME_FILE ]] || { echo "No theme applied yet -- run ubunchy-theme-set first." >&2; exit 1; }
theme=$(<"$THEME_NAME_FILE")
dir="$WALLPAPER_DIR/$theme"

mapfile -d '' -t wallpapers < <(
  find "$dir" -maxdepth 1 -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 2>/dev/null | sort -z
)

if [[ ${#wallpapers[@]} -eq 0 ]]; then
  echo "No wallpapers found for theme '$theme' in $dir" >&2
  exit 1
fi

current=""
[[ -L $CURRENT_LINK ]] && current=$(readlink -f "$CURRENT_LINK")

index=-1
for i in "${!wallpapers[@]}"; do
  if [[ ${wallpapers[$i]} == "$current" ]]; then
    index=$i
    break
  fi
done

if (( index == -1 )); then
  next="${wallpapers[0]}"
else
  next="${wallpapers[$(((index + 1) % ${#wallpapers[@]}))]}"
fi

gsettings set org.gnome.desktop.background picture-uri "file://$next"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$next"
gsettings set org.gnome.desktop.screensaver picture-uri "file://$next"
ln -snf "$next" "$CURRENT_LINK"

echo "Wallpaper -> $next"
OMARCHY_WALLPAPER_NEXT_EOF
chmod +x "$BIN_DIR/ubunchy-wallpaper-next"

log "Installing ubunchy-help..."
cat > "$BIN_DIR/ubunchy-help" <<'OMARCHY_HELP_SCRIPT_EOF'
#!/usr/bin/env python3
"""UbunChy Help -- a tabbed reference window for keyboard shortcuts, CLI
commands, and general UbunChy info, plus a link out to the GitHub repo.

Opened via Super+H, or by running `ubunchy-help` directly.
"""
import os
import subprocess
import sys
import tomllib

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib  # noqa: E402

# TODO: update once the UbunChy repo is public / shared.
GITHUB_URL = "https://github.com/REPLACE-ME/UbunChy"

LOCK_PATH = os.path.expanduser("~/.cache/ubunchy-help.lock")

STATE_DIR = os.path.expanduser("~/.local/state/ubunchy-theme")
CURRENT_THEME_NAME_FILE = os.path.join(STATE_DIR, "current", "theme.name")
THEME_CACHE_DIR = os.path.join(STATE_DIR, "cache", "themes")

SHORTCUTS = [
    ("Super + H", "Open this help window"),
    ("Super + T", "Open your default terminal"),
    ("Super + Ctrl + A", "Open the Agents launcher (Claude, Codex, Gemini, Interpreter, OpenCode)"),
    ("Super + Ctrl + Space", "Open the theme picker (live carousel)"),
    ("Super + Space", "Open the app grid / search"),
    ("Super + Space (twice)", "Switch to the windows overview, search stays active"),
    ("Escape", "Close the theme picker / this help window"),
]

COMMANDS = [
    ("ubunchy-theme-set", "Open the live carousel picker"),
    ("ubunchy-theme-set \"Rose Pine\"", "Apply a specific theme by name"),
    ("ubunchy-theme-set --list", "List all available themes (official + custom)"),
    ("ubunchy-theme-set install <git-url>", "Add your own theme from a git repo"),
    ("ubunchy-theme-set --refresh <name>", "Force a fresh re-download instead of using the cache"),
    ("ubunchy-theme-set ubuntu", "Revert to stock Ubuntu (dock, GTK theme, Super+Space, wallpaper, terminal)"),
    ("ubunchy-wallpaper-next", "Cycle to the next wallpaper in the current theme's set"),
    ("ubunchy-help", "Open this help window"),
    ("ubunchy-open-terminal", "Open your default terminal (whatever Super+T opens)"),
    ("ubunchy-agents", "Open the AI Agents launcher (Claude, Codex, Gemini, Interpreter, OpenCode) -- or Super+Ctrl+A"),
]

ABOUT_TEXT = """UbunChy brings Omarchy's theming system to a standard Ubuntu + GNOME desktop.

It pulls real color palettes and app templates straight from the basecamp/omarchy \
GitHub repo and applies them locally -- terminal, editor, wallpaper, lock screen, \
and a matching GTK/shell desktop look for the most popular themes.

It is not a fork or a distro: nothing about your Ubuntu install changes \
structurally. It's a set of small scripts that theme apps you already have, \
and every file it ever touches is backed up first.

Pick "Ubuntu" at the end of the theme list at any time to revert everything \
back to stock Ubuntu defaults.

Use the GitHub icon above to file issues, suggest themes, or see the source."""

# Fallback used when there's no Omarchy theme to inherit from (the "ubuntu"
# pseudo-theme, or no theme applied yet) -- leans on GTK's own symbolic
# colors so it still matches whatever system GTK theme is active.
FALLBACK_CSS = """
.ubunchy-help-key {
    font-family: monospace;
    font-weight: bold;
    padding: 3px 10px;
    margin: 2px 0;
    border-radius: 6px;
    background-color: @theme_bg_color;
    border: 1px solid @borders;
}
.ubunchy-help-github label {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 16px;
}
.ubunchy-help-about {
    font-size: 10.5pt;
}
"""

# Filled in with the active theme's own palette when one is available.
THEMED_CSS_TEMPLATE = """
.ubunchy-help, .ubunchy-help scrolledwindow, .ubunchy-help viewport, .ubunchy-help stack {{
    background-color: {background};
}}
.ubunchy-help label {{
    color: {foreground};
}}
.ubunchy-help headerbar {{
    background-color: {darker_background};
    background-image: none;
    color: {foreground};
    box-shadow: none;
    border-bottom: 1px solid {selection};
}}
.ubunchy-help headerbar button {{
    color: {foreground};
    background-color: transparent;
}}
.ubunchy-help notebook > header {{
    background-color: {dark_background};
    background-image: none;
    border-bottom: 1px solid {selection};
}}
.ubunchy-help notebook > header tabs tab {{
    color: {muted};
    background-color: transparent;
    padding: 6px 14px;
}}
.ubunchy-help notebook > header tabs tab:checked {{
    color: {foreground};
    box-shadow: inset 0 -2px {accent};
}}
.ubunchy-help-key {{
    font-family: monospace;
    font-weight: bold;
    padding: 3px 10px;
    margin: 2px 0;
    border-radius: 6px;
    background-color: {selection};
    color: {foreground};
    border: 1px solid {accent};
}}
.ubunchy-help-desc {{
    color: {muted};
}}
.ubunchy-help-github label {{
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 16px;
    color: {foreground};
}}
.ubunchy-help-about {{
    font-size: 10.5pt;
}}
"""


def load_theme_colors() -> dict | None:
    """Palette of the currently active Omarchy theme, or None if there's
    nothing to inherit from (the "ubuntu" pseudo-theme, or no theme has ever
    been applied) -- callers should fall back to the system GTK theme then."""
    try:
        with open(CURRENT_THEME_NAME_FILE) as f:
            name = f.read().strip()
    except OSError:
        return None
    if not name or name == "ubuntu":
        return None
    try:
        with open(os.path.join(THEME_CACHE_DIR, name, "colors.toml"), "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return None


def build_css(colors: dict | None) -> bytes:
    if colors is None:
        return FALLBACK_CSS.encode()
    fields = {
        "background": colors.get("background"),
        "dark_background": colors.get("dark_background", colors.get("background")),
        "darker_background": colors.get("darker_background", colors.get("dark_background", colors.get("background"))),
        "foreground": colors.get("foreground"),
        "muted": colors.get("muted", colors.get("light_foreground", colors.get("foreground"))),
        "selection": colors.get("selection", colors.get("lighter_background", colors.get("background"))),
        "accent": colors.get("accent", colors.get("blue", colors.get("foreground"))),
    }
    if not all(fields.values()):
        return FALLBACK_CSS.encode()
    return THEMED_CSS_TEMPLATE.format(**fields).encode()


def build_shortcuts_tab() -> Gtk.Widget:
    grid = Gtk.Grid(row_spacing=10, column_spacing=18, margin=18)
    for row, (keys, desc) in enumerate(SHORTCUTS):
        key_label = Gtk.Label(label=keys, xalign=0)
        key_label.get_style_context().add_class("ubunchy-help-key")
        grid.attach(key_label, 0, row, 1, 1)

        desc_label = Gtk.Label(label=desc, xalign=0)
        desc_label.set_line_wrap(True)
        desc_label.get_style_context().add_class("ubunchy-help-desc")
        grid.attach(desc_label, 1, row, 1, 1)
    return _scrollable(grid)


def build_commands_tab() -> Gtk.Widget:
    grid = Gtk.Grid(row_spacing=10, column_spacing=18, margin=18)
    for row, (cmd, desc) in enumerate(COMMANDS):
        cmd_label = Gtk.Label(label=cmd, xalign=0)
        cmd_label.get_style_context().add_class("ubunchy-help-key")
        cmd_label.set_selectable(True)
        grid.attach(cmd_label, 0, row, 1, 1)

        desc_label = Gtk.Label(label=desc, xalign=0)
        desc_label.set_line_wrap(True)
        desc_label.get_style_context().add_class("ubunchy-help-desc")
        grid.attach(desc_label, 1, row, 1, 1)
    return _scrollable(grid)


def build_about_tab() -> Gtk.Widget:
    label = Gtk.Label(label=ABOUT_TEXT, xalign=0, yalign=0)
    label.set_line_wrap(True)
    label.set_margin_start(18)
    label.set_margin_end(18)
    label.set_margin_top(18)
    label.set_margin_bottom(18)
    label.get_style_context().add_class("ubunchy-help-about")
    return _scrollable(label)


def _scrollable(child: Gtk.Widget) -> Gtk.ScrolledWindow:
    scrolled = Gtk.ScrolledWindow()
    scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scrolled.add(child)
    return scrolled


def open_github(_button):
    try:
        subprocess.Popen(["xdg-open", GITHUB_URL], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


class HelpWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="UbunChy Help")
        self.set_default_size(560, 460)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.get_style_context().add_class("ubunchy-help")

        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(build_css(load_theme_colors()))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("UbunChy Help")
        github_button = Gtk.Button(label="")  # nf-fa-github
        github_button.get_style_context().add_class("ubunchy-help-github")
        github_button.set_tooltip_text("Open the UbunChy GitHub repo")
        github_button.connect("clicked", open_github)
        header.pack_end(github_button)
        self.set_titlebar(header)

        notebook = Gtk.Notebook()
        notebook.append_page(build_shortcuts_tab(), Gtk.Label(label="Shortcuts"))
        notebook.append_page(build_commands_tab(), Gtk.Label(label="Commands"))
        notebook.append_page(build_about_tab(), Gtk.Label(label="About"))
        self.add(notebook)

        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()


def _acquire_singleton_lock() -> bool:
    """Returns True if we got the lock (should proceed), False if another
    instance is already running (should exit quietly)."""
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    if os.path.isfile(LOCK_PATH):
        try:
            with open(LOCK_PATH) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            return False  # still running
        except (OSError, ValueError):
            pass  # stale lock, fall through and reclaim it

    with open(LOCK_PATH, "w") as f:
        f.write(str(os.getpid()))

    def _cleanup():
        try:
            os.remove(LOCK_PATH)
        except OSError:
            pass

    import atexit
    atexit.register(_cleanup)
    return True


def main():
    if not _acquire_singleton_lock():
        sys.exit(0)

    win = HelpWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
OMARCHY_HELP_SCRIPT_EOF
chmod +x "$BIN_DIR/ubunchy-help"

log "Installing ubunchy-open-terminal..."
cat > "$BIN_DIR/ubunchy-open-terminal" <<'OMARCHY_OPEN_TERMINAL_EOF'
#!/usr/bin/env bash
# ubunchy-open-terminal [command args...] -- launches whatever GNOME's
# "default terminal" app setting currently points to
# (org.gnome.desktop.default-applications.terminal), so Super+T always
# follows that setting even if it's changed later, rather than being
# hardcoded to one specific terminal app.
#
# With no arguments, just opens an interactive shell (the Super+T case).
# With arguments, runs that command in the terminal instead (e.g. so the
# Agents launcher can open "claude" directly, with nothing else in the
# window) -- using the terminal's own exec-arg convention (e.g. "-e" for
# kitty/xterm, "--" for gnome-terminal) so only the command itself appears,
# no wrapping shell prompt.
set -euo pipefail

term=$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null || true)
term="${term#\'}"
term="${term%\'}"

if [[ -z "$term" ]] || ! command -v "$term" >/dev/null 2>&1; then
  term="x-terminal-emulator"
fi

if [[ $# -eq 0 ]]; then
  exec "$term"
fi

arg=$(gsettings get org.gnome.desktop.default-applications.terminal exec-arg 2>/dev/null || true)
arg="${arg#\'}"
arg="${arg%\'}"
[[ -z "$arg" ]] && arg="--"

exec "$term" "$arg" "$@"
OMARCHY_OPEN_TERMINAL_EOF
chmod +x "$BIN_DIR/ubunchy-open-terminal"

log "Installing ubunchy-agents..."
cat > "$BIN_DIR/ubunchy-agents" <<'OMARCHY_AGENTS_SCRIPT_EOF'
#!/usr/bin/env python3
"""UbunChy Agents -- a small, chrome-free launcher listing AI coding-agent
CLIs (Claude, Codex, Gemini, Interpreter, OpenCode). Type to filter, Up/Down
to move the selection, Enter to launch it -- opens in your default terminal
(via ubunchy-open-terminal), installing it first in the background if it
isn't on this machine yet, so the terminal itself only ever shows the
agent's own CLI, never install output.
"""
import os
import shutil
import subprocess
import sys
import threading
import tomllib

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib  # noqa: E402

LOCK_PATH = os.path.expanduser("~/.cache/ubunchy-agents.lock")
OPEN_TERMINAL = os.path.expanduser("~/.local/bin/ubunchy-open-terminal")

STATE_DIR = os.path.expanduser("~/.local/state/ubunchy-theme")
CURRENT_THEME_NAME_FILE = os.path.join(STATE_DIR, "current", "theme.name")
THEME_CACHE_DIR = os.path.join(STATE_DIR, "cache", "themes")

# Every install command here is user-space (no sudo) -- npm and pip are both
# pointed at ~/.local so nothing needs root, matching the rest of UbunChy.
AGENTS = [
    {
        "id": "claude",
        "name": "Claude",
        "binary": "claude",
        "subtitle": "Anthropic's Claude Code CLI",
        "install_cmd": ["bash", "-c", "curl -fsSL https://claude.ai/install.sh | bash"],
    },
    {
        "id": "codex",
        "name": "Codex",
        "binary": "codex",
        "subtitle": "OpenAI's Codex CLI",
        "install_cmd": ["npm", "install", "-g", "--prefix", os.path.expanduser("~/.local"), "@openai/codex"],
    },
    {
        "id": "gemini",
        "name": "Gemini",
        "binary": "gemini",
        "subtitle": "Google's Gemini CLI",
        "install_cmd": ["npm", "install", "-g", "--prefix", os.path.expanduser("~/.local"), "@google/gemini-cli"],
    },
    {
        "id": "interpreter",
        "name": "Interpreter",
        "binary": "interpreter",
        "subtitle": "Open Interpreter -- runs code from natural language",
        "install_cmd": ["pip3", "install", "--user", "open-interpreter"],
    },
    {
        "id": "opencode",
        "name": "OpenCode",
        "binary": "opencode",
        "subtitle": "SST's OpenCode CLI",
        "install_cmd": ["bash", "-c", "curl -fsSL https://opencode.ai/install | bash"],
    },
]

FALLBACK_CSS = """
window.ubunchy-agents {
    border: 1px solid alpha(#888888, 0.4);
}
.ubunchy-agent-name {
    font-weight: bold;
    font-size: 13pt;
}
.ubunchy-agents-search {
    margin: 8px;
}
"""

THEMED_CSS_TEMPLATE = """
window.ubunchy-agents {{
    border: 1px solid {selection};
}}
.ubunchy-agents, .ubunchy-agents scrolledwindow, .ubunchy-agents viewport, .ubunchy-agents list {{
    background-color: {background};
}}
.ubunchy-agents label {{
    color: {foreground};
}}
.ubunchy-agents row {{
    background-color: transparent;
}}
.ubunchy-agents row:hover {{
    background-color: {selection};
}}
.ubunchy-agents row:selected, .ubunchy-agents row:selected:hover {{
    background-color: {selection};
    box-shadow: inset 3px 0 {accent};
}}
.ubunchy-agent-name {{
    font-weight: bold;
    font-size: 13pt;
    color: {foreground};
}}
.ubunchy-agent-subtitle {{
    color: {muted};
    font-size: 9.5pt;
}}
.ubunchy-agents-search {{
    margin: 8px;
    background-color: {dark_background};
    color: {foreground};
    border: 1px solid {selection};
    box-shadow: none;
}}
.ubunchy-agents-search image {{
    color: {muted};
}}
"""


def load_theme_colors() -> dict | None:
    """Palette of the currently active Omarchy theme, or None if there's
    nothing to inherit from (the "ubuntu" pseudo-theme, or no theme has ever
    been applied) -- callers should fall back to the system GTK theme then."""
    try:
        with open(CURRENT_THEME_NAME_FILE) as f:
            name = f.read().strip()
    except OSError:
        return None
    if not name or name == "ubuntu":
        return None
    try:
        with open(os.path.join(THEME_CACHE_DIR, name, "colors.toml"), "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return None


def build_css(colors: dict | None) -> bytes:
    if colors is None:
        return FALLBACK_CSS.encode()
    fields = {
        "background": colors.get("background"),
        "dark_background": colors.get("dark_background", colors.get("background")),
        "foreground": colors.get("foreground"),
        "muted": colors.get("muted", colors.get("light_foreground", colors.get("foreground"))),
        "selection": colors.get("selection", colors.get("lighter_background", colors.get("background"))),
        "accent": colors.get("accent", colors.get("blue", colors.get("foreground"))),
    }
    if not all(fields.values()):
        return FALLBACK_CSS.encode()
    return THEMED_CSS_TEMPLATE.format(**fields).encode()


class AgentRow(Gtk.ListBoxRow):
    def __init__(self, agent: dict):
        super().__init__()
        self.agent = agent

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(10)
        box.set_margin_bottom(10)
        box.set_margin_start(14)
        box.set_margin_end(14)

        name = Gtk.Label(label=agent["name"], xalign=0)
        name.get_style_context().add_class("ubunchy-agent-name")
        box.pack_start(name, False, False, 0)

        self.subtitle = Gtk.Label(label=agent["subtitle"], xalign=0)
        self.subtitle.get_style_context().add_class("ubunchy-agent-subtitle")
        box.pack_start(self.subtitle, False, False, 0)

        self.add(box)

    def set_status(self, text: str):
        self.subtitle.set_text(text)


class AgentsWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="UbunChy Agents")
        self.set_default_size(380, 400)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.get_style_context().add_class("ubunchy-agents")

        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(build_css(load_theme_colors()))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(outer)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search agents...")
        self.search_entry.get_style_context().add_class("ubunchy-agents-search")
        self.search_entry.connect("changed", self.on_search_changed)
        self.search_entry.connect("key-press-event", self.on_search_key_press)
        outer.pack_start(self.search_entry, False, False, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.set_activate_on_single_click(True)
        self.rows: dict[str, AgentRow] = {}
        for agent in AGENTS:
            row = AgentRow(agent)
            self.listbox.add(row)
            self.rows[agent["id"]] = row
        self.listbox.connect("row-activated", self.on_row_activated)

        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scrolled.add(self.listbox)
        outer.pack_start(self.scrolled, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-out-event", lambda *_: self.close())

        self.refresh_statuses()
        self.on_search_changed(self.search_entry)  # select the first row up front

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()

    # -- search + keyboard navigation ----------------------------------

    def on_search_changed(self, entry: Gtk.SearchEntry):
        query = entry.get_text().strip().lower()
        first_match = None
        for agent in AGENTS:
            row = self.rows[agent["id"]]
            match = query in agent["name"].lower()
            row.set_visible(match)
            if match and first_match is None:
                first_match = row
        if first_match is not None:
            self.listbox.select_row(first_match)
        else:
            self.listbox.unselect_all()

    def on_search_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Down:
            self.move_selection(1)
            return True
        if event.keyval == Gdk.KEY_Up:
            self.move_selection(-1)
            return True
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            row = self.listbox.get_selected_row()
            if row is not None:
                self.on_row_activated(self.listbox, row)
            return True
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def move_selection(self, delta: int):
        visible = [self.rows[a["id"]] for a in AGENTS if self.rows[a["id"]].get_visible()]
        if not visible:
            return
        current = self.listbox.get_selected_row()
        idx = visible.index(current) if current in visible else (0 if delta > 0 else -1)
        idx = max(0, min(len(visible) - 1, idx + delta))
        self.listbox.select_row(visible[idx])

    # -- install + launch -----------------------------------------------

    def refresh_statuses(self):
        for agent in AGENTS:
            row = self.rows[agent["id"]]
            if shutil.which(agent["binary"]) is None:
                row.set_status("Not installed -- select to install & launch")

    def on_row_activated(self, _listbox, row: AgentRow):
        agent = row.agent
        if shutil.which(agent["binary"]):
            self.launch(agent)
            return
        row.set_status("Installing...")
        row.set_sensitive(False)
        threading.Thread(target=self._install_and_launch, args=(agent, row), daemon=True).start()

    def _install_and_launch(self, agent: dict, row: AgentRow):
        try:
            result = subprocess.run(
                agent["install_cmd"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=600,
            )
            ok = result.returncode == 0 and shutil.which(agent["binary"]) is not None
        except Exception:
            ok = False
        GLib.idle_add(self._install_done, agent, row, ok)

    def _install_done(self, agent: dict, row: AgentRow, ok: bool):
        row.set_sensitive(True)
        if ok:
            row.set_status(agent["subtitle"])
            self.launch(agent)
        else:
            row.set_status("Install failed -- select to retry")
        return False

    def launch(self, agent: dict):
        subprocess.Popen(
            [OPEN_TERMINAL, agent["binary"]],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.close()


def _acquire_singleton_lock() -> bool:
    """Returns True if we got the lock (should proceed), False if another
    instance is already running (should exit quietly)."""
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    if os.path.isfile(LOCK_PATH):
        try:
            with open(LOCK_PATH) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            return False  # still running
        except (OSError, ValueError):
            pass  # stale lock, fall through and reclaim it

    with open(LOCK_PATH, "w") as f:
        f.write(str(os.getpid()))

    def _cleanup():
        try:
            os.remove(LOCK_PATH)
        except OSError:
            pass

    import atexit
    atexit.register(_cleanup)
    return True


def main():
    if not _acquire_singleton_lock():
        sys.exit(0)

    win = AgentsWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
OMARCHY_AGENTS_SCRIPT_EOF
chmod +x "$BIN_DIR/ubunchy-agents"

log "Installing the UbunChy app-grid launcher..."
cat > "$APPS_DIR/ubunchy-theme-set.desktop" <<'OMARCHY_DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=UbunChy
Comment=Slide through Omarchy color themes for your desktop and apps
Exec=ubunchy-theme-set
Icon=preferences-desktop-theme
Categories=Settings;DesktopSettings;GTK;
Terminal=false
StartupNotify=true
OMARCHY_DESKTOP_EOF

log "Installing the UbunChy Help launcher..."
cat > "$APPS_DIR/ubunchy-help.desktop" <<'OMARCHY_HELP_DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=UbunChy Help
Comment=Keyboard shortcuts and usage info for UbunChy
Exec=ubunchy-help
Icon=help-about
Categories=Settings;DesktopSettings;GTK;
Terminal=false
StartupNotify=true
OMARCHY_HELP_DESKTOP_EOF

log "Installing the UbunChy Agents launcher..."
cat > "$APPS_DIR/ubunchy-agents.desktop" <<'OMARCHY_AGENTS_DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=UbunChy Agents
Comment=Launch an AI coding agent CLI (Claude, Codex, Gemini, Interpreter, OpenCode)
Exec=ubunchy-agents
Icon=utilities-terminal
Categories=Settings;DesktopSettings;GTK;
Terminal=false
StartupNotify=true
OMARCHY_AGENTS_DESKTOP_EOF

log "Installing README.md..."
cat > "$HOME/README.md" <<'OMARCHY_README_EOF'
# UbunChy

I loved the way Omarchy looked. But Omarchy is a full Arch Linux and Hyprland distro, and I was not ready to leave Ubuntu. I know it well, I have used it as my main OS for a long time, and I did not want to reinstall my whole system, back up every file, and hope nothing breaks, just for a nicer desktop.

So I built UbunChy. It brings the Omarchy look to Ubuntu and GNOME, no new distro, no backups, no risk to your files. Thank you [DHH](https://github.com/DHH), and the whole Omarchy project, for the inspiration. If you already know Omarchy, you know what this is about.

UbunChy pulls the real color palettes and app templates straight from [basecamp/omarchy](https://github.com/basecamp/omarchy) on GitHub and applies them locally, plus a matching GTK and shell look for the most popular themes. And like Omarchy, UbunChy is AI driven too, with an agent launcher built in for Claude, Codex, Gemini, Interpreter, and OpenCode.

It is **not** a fork or a distro. Nothing about your Ubuntu install changes structurally. It's a set of small scripts that theme apps you already have.

## Features

### Theme switching
- **All 22 official Omarchy themes** — Tokyo Night, Catppuccin, Catppuccin Latte, Rosé Pine, Gruvbox, Nord, Everforest, Kanagawa, Osaka Jade, Flexoki Light, and 12 more — fetched live from GitHub, always up to date with upstream.
- **Live, borderless carousel picker** — a transparent, chrome-free window floating over your desktop: just the current theme's preview image, dimmed previews of the theme on either side so you can see what's next before you move, and the name below. Slide with the arrow keys, scroll wheel, or by clicking a side preview, and it applies automatically as you land on one — no Apply button, no click required, no window decoration to close (Escape, or click away). Rapid sliding is debounced so it only ever commits the theme you actually settle on, never the ones you passed through. Opens automatically when you run `ubunchy-theme-set` with no arguments.
- **Global keyboard shortcut** — `Super+Ctrl+Space` opens the picker from anywhere.
- **UbunChy Help** — `Super+H` opens a tabbed reference window: keyboard shortcuts, CLI commands, and a short "what is this" tab, plus a GitHub icon in the title bar linking to this repo. It's colored using the currently active Omarchy theme's own palette (background, text, accent, tab highlight — read straight from that theme's resolved `colors.toml`), so it always matches whatever you're running; picking "Ubuntu" falls it back to the plain system GTK look. Also in Activities as "UbunChy Help", or run `ubunchy-help`.
- **Open a terminal** — `Super+T` opens whatever GNOME's default-terminal setting currently points to (via `ubunchy-open-terminal`, which reads that setting fresh each time, so it stays correct even if you change your default terminal later).
- **Super+Space app launcher, dock hidden** — matches Omarchy's own `Super+Space` app finder: a full-screen search-as-you-type app grid (GNOME's built-in app view, rebound from its default of switching keyboard layout, which nothing here uses). The dock is set to auto-hide so it's this instead of a pinned sidebar. **Press it twice** and it switches from the app grid into GNOME's windows overview — live thumbnails of every open window, still with the search field active; arrow keys move the selection, Enter switches to it. (Verified by literally simulating the keypresses and screenshotting the result — this isn't a guess.) This is reasserted on every real theme you switch to, so it can't be left in the wrong state by having picked "Ubuntu" earlier.
- **App-grid launcher** — "UbunChy" shows up in Activities like any other app.
- **Custom themes** — `ubunchy-theme-set install <git-url>` adds your own theme (any repo with a `colors.toml` at its root) alongside the official 22.
- **"Ubuntu" — revert to stock** — a 23rd entry at the end of the carousel/list that isn't an Omarchy theme at all: it's the only one where the dock is shown (pinned, like a fresh install) and `Super+Space` goes back to switching keyboard layout. It reverts GTK/icon theme, GNOME Shell theme, the dock, `Super+Space`, wallpaper, and GNOME Terminal colors back to their real factory-default values (via `gsettings reset`/`dconf reset`, not hardcoded guesses — checked against Ubuntu's own `/usr/share/glib-2.0/schemas/10_ubuntu*.gschema.override` files). Picking any other theme afterward flips the dock and `Super+Space` straight back to UbunChy's own behavior. Per-app configs themed along the way (Kitty, VS Code, Neovim, ...) are left as they are — pick any real theme again to re-theme those.
- **Fast** — themes you've already applied once are cached; switching back to one takes well under a second.

### AI agents
- **UbunChy Agents** — `Super+Ctrl+A` opens a small, chrome-free launcher listing five AI coding-agent CLIs: **Claude** (Claude Code), **Codex** (OpenAI's Codex CLI), **Gemini** (Gemini CLI), **Interpreter** (Open Interpreter), and **OpenCode**. Just start typing to filter by name, `↑`/`↓` to move the selection, `Enter` to launch it — or click a row directly. It opens in your default terminal (whatever `Super+T` opens), running only that agent — no wrapper shell, no install output. Also colored using the active theme's palette, same as UbunChy Help; closes on Escape or on losing focus, same as the theme picker. Also in Activities as "UbunChy Agents", or run `ubunchy-agents`.
- **Installed for you** — the bootstrap script installs all five up front (skipping any already present), entirely user-space: Claude and OpenCode via their own official installers (to `~/.local`), Codex and Gemini via `npm install -g --prefix ~/.local`, Interpreter via `pip3 install --user` — no sudo needed for any of them. If one was missing or failed to install (no network, etc.), selecting it in the Agents window installs it in the background the same way, then launches it automatically once ready.

### What actually gets themed
- **Terminal**: Alacritty, Kitty, Foot, Ghostty, and **GNOME Terminal** (via its dconf profile — the one most people are actually running), including a 7%-transparent background baked in on every switch, so it always looks like this rather than needing to be set by hand (see `GNOME_TERMINAL_TRANSPARENCY_PERCENT` in `UbunChy-theme-apply.sh` to change it)
- **Live color reload** — retints the terminal you ran the command from *instantly*, via OSC escape codes, no new window needed
- **Editors**: Neovim (colorscheme), VS Code / VS Code Insiders / VSCodium / Cursor (installs the real published theme extension when the Omarchy theme names one, e.g. `enkia.tokyo-night`, else generates a local one)
- **Claude Code** (the CLI you're reading this from, if that's how you got here)
- **btop**, **Helix**, **Obsidian** (per-vault)
- **Chromium-family browsers** (Chromium, Chrome, Edge, Brave) — matches the browser chrome color
- **Wallpaper + lock screen** — sets both, and `ubunchy-wallpaper-next` cycles through a theme's full wallpaper set
- **GTK app style + GNOME Shell (top bar)** — for 13 of the 22 themes: **Tokyo Night, Catppuccin, Catppuccin Latte, Rosé Pine, Gruvbox, Nord, Everforest, Kanagawa, Hackerman (Matrix), Osaka Jade, Vantablack, Matte Black, White**. The other 9 (Ethereal, Flexoki Light, Last Horizon, Lumon, Lupine, Miasma, Retro 82, Ristretto, Solitude) still correctly color every app above; they just don't currently change your GTK/shell chrome — no good matching GTK theme has been found for them yet. This includes GTK4/libadwaita apps (Files, Text Editor, Console, ...) — those ignore the classic `gtk-theme` setting entirely and only read `~/.config/gtk-4.0/gtk.css`, which `ubunchy-theme-set` links in from the active theme automatically. Files (Nautilus) specifically keeps a persistent background service alive between windows for fast launches, which would otherwise keep showing whatever theme was active when it last started — `ubunchy-theme-set` quits that service on every switch so the next time you open Files, it comes back up already on the new theme.

### Safety
- **Every file this ever touches is backed up first**, timestamped, before any change — including a full `dconf dump` of your GNOME Terminal profile, restorable with one command.
- Nothing is ever silently overwritten: if an app's config already has custom theming you set up yourself, it's left alone with a note instead.

## Installation

One command, pulls the script straight from this repo and runs it:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bunkeriot/ubunchy/main/UbunChy-desktop-bootstrap.sh)"
```

Or, if you'd rather read it first, clone the repo and run it yourself:

```
git clone https://github.com/bunkeriot/ubunchy.git
cd ubunchy
chmod +x UbunChy-desktop-bootstrap.sh
./UbunChy-desktop-bootstrap.sh
```

One sudo prompt (package installs); everything else is user-space. Safe to re-run any time. Log out and back in once afterward — GNOME only picks up newly installed Shell extensions at login.

## Usage

```
ubunchy-theme-set                    # live carousel picker (or press Super+Ctrl+Space)
ubunchy-theme-set "Rose Pine"        # apply a specific theme by name
ubunchy-theme-set --list             # list all available themes (official + custom)
ubunchy-theme-set install <git-url>  # add your own theme from a git repo
ubunchy-theme-set --refresh <name>   # force a fresh re-download instead of using the cache
ubunchy-theme-set ubuntu             # revert to stock Ubuntu (dock, GTK theme, Super+Space, wallpaper, terminal)

ubunchy-wallpaper-next               # cycle to the next wallpaper in the current theme's set
ubunchy-help                         # shortcuts/commands/about window (or press Super+H)
ubunchy-open-terminal                # open your default terminal (or press Super+T)
ubunchy-agents                       # AI agent launcher (Claude, Codex, Gemini, Interpreter, OpenCode)
```

## How it works

- `UbunChy-theme-apply.sh` is the engine: it downloads a theme's `colors.toml` and the shared app templates from `basecamp/omarchy` on GitHub, resolves the full color palette (a self-contained port of Omarchy's own `omarchy-theme-color` alias/fallback logic), renders the templates, and applies the result to every installed app — each with its own backup-first, idempotent integration.
- `ubunchy-theme-set` is the friendly wrapper: resolves the theme name, calls the engine, and additionally sets the matching GTK/icon/shell theme via `gsettings` for the 13 themes that have one installed. `ubuntu` is special-cased here — it's not a real Omarchy theme (no `colors.toml` upstream), so it skips the engine entirely and instead resets every gsetting/dconf key this project touches back to Ubuntu's real default.
- `ubunchy-theme-picker` is the live carousel — called automatically by `ubunchy-theme-set` when no theme name is given, and applies each theme itself (via `ubunchy-theme-set`) as you slide, debounced so a quick browse-through only commits the one you stop on.
- `ubunchy-wallpaper-next` is a small standalone script for cycling wallpapers independent of a full theme switch.
- `ubunchy-help` is a standalone GTK window (no dependency on the other scripts) with Shortcuts/Commands/About tabs and a GitHub link; single-instance, so pressing `Super+H` again while it's open won't spawn a second copy.
- `ubunchy-open-terminal` is a one-line wrapper: it reads `org.gnome.desktop.default-applications.terminal` fresh on every launch and execs that, so `Super+T` always opens whatever your actual default terminal is, even if you change it later. It also accepts a command (`ubunchy-open-terminal claude`), in which case it runs that instead of an interactive shell, using the terminal's own exec-arg convention (`-e` for kitty/xterm, `--` for gnome-terminal) so only the command itself shows up, nothing else.
- `ubunchy-agents` is the AI agent launcher: each row checks `command -v` for that agent's binary, and if it's missing, installs it (same install commands as the bootstrap step, run off the GTK thread) before launching it via `ubunchy-open-terminal <binary>` and closing the window.

Everything lives under `~/.local/state/ubunchy-theme/` (cache, rendered output, backups) and `~/.themes` (GTK themes), with the scripts themselves in `~/` and `~/.local/bin/`.

## What's not included

- 13 of the 22 themes have a matching GTK/shell desktop look built — the other 9 (Ethereal, Flexoki Light, Last Horizon, Lumon, Lupine, Miasma, Retro 82, Ristretto, Solitude) theme every app correctly but leave your GTK chrome as-is, since no good matching GTK theme has been found for them yet. More can be added the same way (see `DESKTOP_MAP` in `ubunchy-theme-set`).
- Firefox isn't themed (real Omarchy doesn't theme it either — only Chromium-family browsers).
- The exact original build recipe for the bundled "Tokyonight-Dark-Storm" GTK theme predates this project's history and isn't reproducible byte-for-byte; the bootstrap script rebuilds an equivalent from the same upstream engine.

## Support

I built UbunChy in my spare time, mostly at night, because I wanted this to exist and nobody else was building it. It's free, it's open source, and that's not changing.

If it saved you the trouble of reinstalling your whole OS just to get a nicer desktop, and you'd like to buy me a coffee for it, there's a Sponsor button at the top of this repo. No pressure, no tiers, no strings. Stars, issues, and pull requests are just as welcome, and just as appreciated.

## Credits

UbunChy doesn't invent any of the design — it's a delivery mechanism for other people's excellent work:

- **[basecamp/omarchy](https://github.com/basecamp/omarchy)**, and **[DHH](https://github.com/DHH)** who built it — the theme palettes, app templates, and the whole theming concept this project ports (MIT licensed)
- **[Fausto-Korpsvart](https://github.com/Fausto-Korpsvart)** — Tokyo Night, Catppuccin, Rosé Pine, Gruvbox, Everforest, Kanagawa, Matrix, Osaka, and Colloid GTK theme engines
- **[EliverLara/Nordic](https://github.com/EliverLara/Nordic)** — the Nord GTK theme
- **[Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)** — icon theme
- **[Nerd Fonts](https://github.com/ryanoasis/nerd-fonts)** — JetBrains Mono Nerd Font
- **GNOME Shell extension authors** — User Themes (fmuellner), Blur my Shell (aunetx), Just Perfection

## License

The scripts here are yours to do whatever you want with. The themes, fonts, icons, and GTK engines they pull in each carry their own upstream licenses (all MIT/GPL-family, all open source) — see the links above.
OMARCHY_README_EOF

# ---------------------------------------------------------------------------
# 6. AI agent CLIs for the Agents launcher (Claude, Codex, Gemini,
#    Interpreter, OpenCode) -- each installed user-space, no sudo, skipped
#    if already present. Any that fail here (e.g. no network) can be
#    retried later by just selecting them in the Agents window, which
#    installs the same way.
# ---------------------------------------------------------------------------

log "Installing AI agent CLIs used by the Agents launcher (skipping any already installed)..."

if ! command -v claude >/dev/null 2>&1; then
  log "Installing Claude Code CLI..."
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install failed -- you can retry later from the Agents window."
fi

if ! command -v codex >/dev/null 2>&1; then
  log "Installing Codex CLI..."
  npm install -g --prefix "$HOME/.local" @openai/codex || warn "Codex CLI install failed -- you can retry later from the Agents window."
fi

if ! command -v gemini >/dev/null 2>&1; then
  log "Installing Gemini CLI..."
  npm install -g --prefix "$HOME/.local" @google/gemini-cli || warn "Gemini CLI install failed -- you can retry later from the Agents window."
fi

if ! command -v interpreter >/dev/null 2>&1; then
  log "Installing Open Interpreter..."
  pip3 install --user open-interpreter || warn "Open Interpreter install failed -- you can retry later from the Agents window."
fi

if ! command -v opencode >/dev/null 2>&1; then
  log "Installing OpenCode CLI..."
  curl -fsSL https://opencode.ai/install | bash || warn "OpenCode install failed -- you can retry later from the Agents window."
fi

# ---------------------------------------------------------------------------
# 7. Set the initial desktop state and do a real first theme apply
# ---------------------------------------------------------------------------

log "Setting initial GTK/icon/dark-mode defaults..."
gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Dark-Storm' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

USER_THEME_SCHEMA_DIR="$EXT_DIR/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
if [[ -d $USER_THEME_SCHEMA_DIR ]]; then
  gsettings --schemadir "$USER_THEME_SCHEMA_DIR" set org.gnome.shell.extensions.user-theme name 'Tokyonight-Dark-Storm' 2>/dev/null || true
fi

update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

log "Running an initial theme apply (Tokyo Night) to land in a known-good state..."
"$BIN_DIR/ubunchy-theme-set" "Tokyo Night" || warn "Initial theme apply hit an issue -- you can retry any time with: ubunchy-theme-set 'Tokyo Night'"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

cat <<'EOF'

==============================================================================
 UbunChy desktop bootstrap complete.
==============================================================================

Installed:
  - GTK/shell themes for 13 of the 22 official Omarchy themes (~/.themes):
    Tokyo Night, Catppuccin, Catppuccin Latte, Rose Pine, Gruvbox, Nord,
    Everforest, Kanagawa, Hackerman (Matrix), Osaka Jade, Vantablack,
    Matte Black, White (plain Adwaita)
  - Papirus-Dark icon theme
  - GNOME Shell extensions: User Themes, Blur my Shell, Just Perfection
  - JetBrains Mono Nerd Font
  - gnome-tweaks and Extension Manager (for browsing/picking themes visually)
  - Chromium-family browser theming enabled (for whichever of Chromium/Chrome/
    Edge/Brave are actually installed)
  - GTK4/libadwaita apps (Files, Text Editor, Console, ...) themed too, via
    ~/.config/gtk-4.0 -- these ignore the classic GTK3 theme setting
    entirely. Files' persistent background service is restarted on every
    switch so it actually picks up the change instead of needing a
    manual restart.
  - Super+Ctrl+Space keyboard shortcut -> opens the theme picker
  - Super+H keyboard shortcut         -> opens UbunChy Help
  - Super+T keyboard shortcut         -> opens your default terminal
  - Super+Ctrl+A keyboard shortcut    -> opens the Agents launcher
  - ~/.local/bin/ubunchy-help         (tabbed shortcuts/commands/about window,
                                        with a GitHub link -- also in the app
                                        grid as "UbunChy Help")
  - ~/.local/bin/ubunchy-open-terminal (reads your GNOME default-terminal
                                         setting fresh each launch)
  - ~/.local/bin/ubunchy-agents       (AI agent launcher: Claude, Codex,
                                        Gemini, Interpreter, OpenCode --
                                        type to filter, arrow keys + Enter
                                        to launch; also in the app grid as
                                        "UbunChy Agents")
  - AI agent CLIs (Claude Code, Codex CLI, Gemini CLI, Open Interpreter,
    OpenCode),
    installed user-space (no sudo) if they weren't already on this machine
  - ~/UbunChy-theme-apply.sh          (fetches any of the 22 official Omarchy
                                        themes, or a custom one you installed,
                                        and applies them to installed apps --
                                        terminal, GNOME Terminal, editor, VS
                                        Code, Claude Code, Obsidian, browser,
                                        wallpaper, lock screen, and live OSC
                                        color reload of the running terminal)
  - ~/.local/bin/ubunchy-theme-set    (the unified switcher)
  - ~/.local/bin/ubunchy-theme-picker (live, borderless carousel -- slide with
                                        arrow keys/scroll/click and it applies
                                        automatically; used automatically when
                                        no theme name is given)
  - ~/.local/bin/ubunchy-wallpaper-next (cycle to the next wallpaper in the
                                          current theme's set)
  - "UbunChy" entry in your app grid (Activities -> search "UbunChy")

ONE THING LEFT: log out and back in once. GNOME Shell only picks up newly
installed extensions (and a just-disabled default one, like the Ubuntu Dock
here) at login -- until then the shell/top-bar theme, Blur my Shell / Just
Perfection, and the hidden dock won't be fully in effect, even though GTK app
colors, icons, dark mode, and Super+Space already are.

After logging back in:
  ubunchy-theme-set                 # live carousel picker (or Super+Ctrl+Space)
  ubunchy-theme-set "Rose Pine"     # apply a specific theme by name
  ubunchy-theme-set --list          # see all theme names, official + custom
  ubunchy-theme-set install <url>   # add your own theme from a git repo
  ubunchy-theme-set ubuntu          # revert to stock Ubuntu (dock, GTK theme, Super+Space, wallpaper, terminal)
  ubunchy-wallpaper-next            # cycle to the next wallpaper in the set
  ubunchy-help                      # shortcuts/commands/about window (or Super+H)
  ubunchy-open-terminal              # open your default terminal (or Super+T)
  ubunchy-agents                     # AI agent launcher (Claude, Gemini, Interpreter, OpenCode)

The other 9 Omarchy themes (Ethereal, Flexoki Light, Last Horizon, Lumon,
Lupine, Miasma, Retro 82, Ristretto, Solitude) don't have a matching GTK
theme built yet -- they still correctly theme your terminal, editor, Claude
Code, VS Code, browser, and wallpaper, just not the GTK/shell chrome itself.
==============================================================================
EOF
