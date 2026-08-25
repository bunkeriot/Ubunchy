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
