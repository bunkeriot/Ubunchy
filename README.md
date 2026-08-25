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
