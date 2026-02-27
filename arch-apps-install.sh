#!/usr/bin/env bash
# =============================================================================
#  arch-apps-install.sh — NIRUCON Application Layer for Arch Linux
#  Author: Nicklas Rudolfsson (nirucon)
#  Part of: https://github.com/nirucon/niri
#
#  Companion script to alpi-niri.sh.
#  That script installs the Wayland compositor stack (niri, waybar, foot…).
#  This script installs the application layer on top: browsers, media, dev
#  tools, CLI utilities, and configures qutebrowser out of the box.
#
#  Design principles:
#  - Idempotent: safe to run multiple times (--needed everywhere)
#  - Non-destructive: backs up existing configs before touching them
#  - Categorised: every package is commented so you know why it is here
#  - Self-contained: bootstraps yay if it is missing
#  - Composable: qutebrowser config uses managed blocks that can be
#    re-applied cleanly on every 'update' run
#
#  Modes:
#    install    Bootstrap yay, install all packages, configure qutebrowser
#    update     Re-sync packages (--needed) and re-apply qutebrowser config
#    dry-run    Preview all actions — zero changes made
#    verify     Check that expected commands and config files are present
#
#  Usage:
#    ./arch-apps-install.sh install
#    ./arch-apps-install.sh update
#    ./arch-apps-install.sh dry-run
#    ./arch-apps-install.sh verify
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# PACKAGES
#
# Each package has an inline comment explaining what it is and why it is here.
# Add or remove packages freely — the --needed flag means already-installed
# packages are silently skipped, so running install/update is always safe.
# =============================================================================

# ── Official Arch repositories ────────────────────────────────────────────────

PACMAN_PKGS=(
    # ── Browsers ──────────────────────────────────────────────────────────────
    qutebrowser                 # keyboard-driven, Python/WebKit browser
    python-adblock              # native ABP-compatible adblock engine for qutebrowser

    # ── Terminal & shell utilities ─────────────────────────────────────────────
    htop                        # interactive process viewer
    btop                        # modern resource monitor (htop alternative)
    fastfetch                   # system info display (neofetch replacement)
    tree                        # directory tree listing
    less                        # pager for reading long output
    rsync                       # fast file transfer / sync
    unzip zip tar               # archive tools
    curl wget                   # file download tools
    jq                          # JSON processor (useful with scripts)
    fzf                         # fuzzy finder (used by many CLI tools)
    ripgrep                     # fast grep replacement (used by neovim/fzf)
    fd                          # fast find replacement
    zoxide                      # smarter cd — learns your most-used dirs
    bat                         # cat with syntax highlighting and git diff
    eza                         # modern ls replacement with icons and git info
    yazi                        # terminal file manager with previews
    lazygit                     # terminal UI for git
    bash-completion             # tab completion for bash
    bc                          # arbitrary-precision calculator

    # ── Text editors ──────────────────────────────────────────────────────────
    neovim                      # extensible terminal text editor
    python-pynvim               # Python provider for neovim plugins

    # ── Development tools ─────────────────────────────────────────────────────
    git                         # version control (probably already present)
    base-devel                  # make, gcc, pkgconf — needed for AUR and compiling
    nodejs                      # JavaScript runtime (needed by many neovim LSPs)
    npm                         # Node package manager
    python                      # Python interpreter
    python-pip                  # Python package installer

    # ── File management ────────────────────────────────────────────────────────
    pcmanfm                     # lightweight GTK file manager
    gvfs                        # virtual filesystem (enables trash, network mounts)
    gvfs-mtp                    # MTP support (Android phones via USB)
    gvfs-gphoto2                # gPhoto2 support (cameras)
    udisks2                     # disk management daemon (automounting)
    udiskie                     # automount tray applet (uses udisks2)
    7zip                        # 7z archiver (also handles rar, zip etc.)
    poppler                     # PDF rendering library (needed by many viewers)

    # ── Media ─────────────────────────────────────────────────────────────────
    mpv                         # versatile video/audio player (plays anything)
    yt-dlp                      # download YouTube and 500+ sites; mpv backend
    cmus                        # ncurses music player (light, keyboard-driven)
    cava                        # terminal audio spectrum visualizer
    playerctl                   # MPRIS media player control (play/pause/next)
    imagemagick                 # image conversion/manipulation from CLI
    gimp                        # GNU image manipulation program
    sxiv                        # simple X image viewer (fast, minimal)
    resvg                       # SVG renderer — used by some status-bar scripts

    # ── Screenshots & screen tools ─────────────────────────────────────────────
    grim                        # Wayland screenshot tool
    slurp                       # Wayland region selector (used with grim)
    wl-clipboard                # Wayland clipboard (wl-copy / wl-paste)

    # ── Fonts ─────────────────────────────────────────────────────────────────
    ttf-dejavu                  # fallback sans/mono font
    noto-fonts                  # broad Unicode coverage
    noto-fonts-emoji            # emoji glyphs
    ttf-nerd-fonts-symbols-mono # icon glyphs used in status bars / prompts

    # ── Theming & appearance ───────────────────────────────────────────────────
    lxappearance                # GTK theme/font/icon switcher
    materia-gtk-theme           # modern flat dark GTK theme
    papirus-icon-theme          # clean icon theme with many app icons
    qt5ct                       # Qt5 appearance config tool
    qt6ct                       # Qt6 appearance config tool
    qt5-base                    # Qt5 base libraries
    qt6-base                    # Qt6 base libraries
    kvantum                     # Qt SVG theming engine (works with qt5ct/qt6ct)

    # ── Networking ────────────────────────────────────────────────────────────
    openssh                     # SSH client and server
    networkmanager              # network management (likely already enabled)

    # ── Bluetooth ─────────────────────────────────────────────────────────────
    blueman                     # Bluetooth manager GUI

    # ── Notifications ─────────────────────────────────────────────────────────
    libnotify                   # send desktop notifications from CLI

    # ── Wallpapers ────────────────────────────────────────────────────────────
    swaybg                      # set wallpaper on Wayland (niri uses this)

    # ── Cloud & sync ──────────────────────────────────────────────────────────
    nextcloud-client            # Nextcloud desktop sync client

    # ── Misc CLI ──────────────────────────────────────────────────────────────
    xdg-utils                   # xdg-open and friends (open files with default app)
)

# ── AUR packages ──────────────────────────────────────────────────────────────

AUR_PKGS=(
    ttf-jetbrains-mono-nerd     # preferred monospace nerd font (terminal + editor)
    brave-bin                   # privacy-focused Chromium-based browser
    spotify                     # Spotify music streaming client
    localsend-bin               # AirDrop alternative, cross-platform LAN sharing
    reversal-icon-theme-git     # alternative icon theme
    fresh-editor-bin            # Fresh text editor (simple, fast, GTK)
)

# =============================================================================
# COLORS / LOGGING — identical style to alpi-niri.sh
# =============================================================================

NC="\033[0m"
GRN="\033[1;32m"
RED="\033[1;31m"
YLW="\033[1;33m"
BLU="\033[1;34m"
CYN="\033[1;36m"
MAG="\033[1;35m"

say()  { printf "${BLU}[APPS]${NC} %s\n" "$*"; }
step() { printf "${MAG}[====]${NC} %s\n" "$*"; }
ok()   { printf "${GRN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
info() { printf "${CYN}[INFO]${NC} %s\n" "$*"; }
die()  { fail "$@"; exit 1; }

trap 'fail "Unexpected error at line $LINENO — command: ${BASH_COMMAND:-?}"' ERR

# =============================================================================
# MODE
# =============================================================================

MODE="${1:-}"

usage() {
    cat <<'EOF'
arch-apps-install.sh — NIRUCON Application Layer for Arch Linux

USAGE:
  ./arch-apps-install.sh <mode>

MODES:
  install    Bootstrap yay + install all packages + configure qutebrowser
  update     Re-sync packages (--needed) and re-apply qutebrowser config
  dry-run    Preview all actions — no changes made
  verify     Check that expected commands and config files are in place

EXAMPLES:
  ./arch-apps-install.sh install
  ./arch-apps-install.sh update
  ./arch-apps-install.sh dry-run
  ./arch-apps-install.sh verify
EOF
}

case "$MODE" in
    install|update|dry-run|verify) ;;
    -h|--help|help) usage; exit 0 ;;
    "") usage; die "No mode specified." ;;
    *) usage; die "Unknown mode: '$MODE'" ;;
esac

DRY_RUN=0
[[ "$MODE" == "dry-run" ]] && DRY_RUN=1

# =============================================================================
# ROOT GUARD — never run as root; sudo is called internally where needed
# =============================================================================

[[ ${EUID:-$(id -u)} -ne 0 ]] || \
    die "Do not run as root. Run as your normal user (with sudo rights)."

# =============================================================================
# CORE HELPERS
# =============================================================================

# run: execute a command, or just print it in dry-run mode.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        "$@"
    fi
}

# run_sh: like run() but uses bash -c for commands that need shell features.
run_sh() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        bash -c "$*"
    fi
}

# ensure_dir: create a directory if it does not exist.
ensure_dir() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] mkdir -p $*"
    else
        mkdir -p "$@"
    fi
}

# timestamp: current date-time string for backup file names.
timestamp() { date +"%Y%m%d_%H%M%S"; }

# =============================================================================
# BOOTSTRAP
# Ensure git, base-devel, and yay are available.
# Called at the start of both 'install' and 'update' to be safe.
# =============================================================================

bootstrap() {
    step "Bootstrap: ensuring git, base-devel, and yay are available"

    # Sync pacman package databases first — essential on a fresh system
    say "Syncing pacman databases..."
    run sudo pacman -Sy --noconfirm

    # git is needed to clone AUR packages (and to build yay itself)
    if ! command -v git >/dev/null 2>&1; then
        say "git not found — installing..."
        run sudo pacman -S --needed --noconfirm git
    else
        info "git: $(command -v git)"
    fi

    # base-devel is required by makepkg to build any AUR package
    if ! pacman -Qq base-devel >/dev/null 2>&1; then
        say "base-devel not found — installing..."
        run sudo pacman -S --needed --noconfirm base-devel
    else
        info "base-devel: already installed"
    fi

    # yay: build from AUR if not present
    if ! command -v yay >/dev/null 2>&1; then
        say "yay not found — building from AUR..."
        local tmp
        tmp="$(mktemp -d)"
        # shellcheck disable=SC2064
        trap "rm -rf '$tmp'" RETURN
        run git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        ( cd "$tmp/yay-bin" && run makepkg -si --noconfirm )
        ok "yay installed"
    else
        info "yay: $(command -v yay)"
    fi
}

# =============================================================================
# INSTALL PACKAGES
# =============================================================================

install_packages() {
    step "Installing packages"

    say "Installing ${#PACMAN_PKGS[@]} pacman packages (--needed skips existing)..."
    run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

    say "Installing ${#AUR_PKGS[@]} AUR packages via yay..."
    run yay -S --needed --noconfirm "${AUR_PKGS[@]}"

    ok "Packages done"
}

# =============================================================================
# LAZYVIM BOOTSTRAP
#
# Bootstraps LazyVim (https://www.lazyvim.org) as the neovim config if no
# ~/.config/nvim directory exists yet. Completely non-destructive: if you
# already have a neovim config it is left entirely untouched.
#
# LazyVim gives a batteries-included neovim experience with LSP, treesitter,
# fuzzy finding, and a curated set of plugins — all managed by lazy.nvim.
# =============================================================================

bootstrap_lazyvim() {
    step "Neovim / LazyVim"

    local nvim_dir="$HOME/.config/nvim"

    if ! command -v nvim >/dev/null 2>&1; then
        warn "neovim not found — skipping LazyVim bootstrap"
        return 0
    fi

    if [[ -d "$nvim_dir" ]]; then
        info "~/.config/nvim already exists — leaving neovim config untouched"
        return 0
    fi

    say "No neovim config found — bootstrapping LazyVim..."

    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] Would clone LazyVim starter into $nvim_dir"
        say "[dry-run] Would run: nvim --headless '+Lazy! sync' +qa"
        return 0
    fi

    git clone --depth=1 https://github.com/LazyVim/starter "$nvim_dir"
    # Remove the .git directory so the config is free from the starter repo
    rm -rf "$nvim_dir/.git"

    say "Running LazyVim initial plugin sync (this may take a minute)..."
    # +qa exits neovim after the sync. '|| true' prevents a non-zero exit from
    # a first-run LSP download from aborting the whole script.
    nvim --headless "+Lazy! sync" +qa || \
        warn "LazyVim sync returned non-zero — plugins will finish on first launch"

    ok "LazyVim installed at $nvim_dir"
}

# =============================================================================
# CONFIGURE QUTEBROWSER
#
# Applies three managed blocks to ~/.config/qutebrowser/config.py:
#
#   1) adblock + YouTube helpers   (adblock lists, mpv keybind, piped.video)
#   2) dark UI + prefer-dark pages (UI palette, preferred_color_scheme=dark)
#   3) privacy + performance       (3rd-party cookies, canvas, cache, etc.)
#
# Each block is idempotent: it is removed and re-written on every run so
# 'update' always reflects the current settings in this script.
#
# A timestamped backup of config.py is made before any modification.
# =============================================================================

configure_qutebrowser() {
    step "Configuring qutebrowser"

    local config_dir="$HOME/.config/qutebrowser"
    local config_file="$config_dir/config.py"
    local userscripts_dir="$HOME/.local/share/qutebrowser/userscripts"

    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] Would configure qutebrowser at $config_file"
        say "[dry-run] Would install userscript: $userscripts_dir/youtube-to-piped"
        return 0
    fi

    # ── Create directories ────────────────────────────────────────────────────
    mkdir -p "$config_dir" "$userscripts_dir"

    # ── Create a minimal config.py if none exists ─────────────────────────────
    if [[ ! -f "$config_file" ]]; then
        say "Creating new config.py..."
        cat > "$config_file" <<'EOF'
# Qutebrowser config file — generated by arch-apps-install.sh
# This file is executed as Python code.
EOF
    fi

    # ── Backup before modifying ───────────────────────────────────────────────
    local backup="${config_file}.bak.$(timestamp)"
    say "Backup: $backup"
    cp -a "$config_file" "$backup"

    # ── Repair: remove any empty try/except blocks left by old scripts ─────────
    # Some older config scripts wrapped settings in try/except and could leave
    # empty blocks behind that make config.py unparseable by Python.
    say "Repairing any empty try/except blocks..."
    python3 - <<'PY'
from pathlib import Path
import re

p = Path.home() / ".config/qutebrowser/config.py"
s = p.read_text(encoding="utf-8")

# Remove try: blocks where the try body is empty (only followed by except)
s = re.sub(r'^\s*try:\s*\n(?=\s*except\b)', '', s, flags=re.M)
# Remove orphaned "except ...: \n    pass" lines
s = re.sub(r'^\s*except\b[^\n]*:\s*\n\s*pass\s*\n', '', s, flags=re.M)

p.write_text(s, encoding="utf-8")
PY

    # ── Helper: remove a managed block from config.py (idempotent) ────────────
    # Arguments: begin-marker end-marker
    remove_block() {
        local begin="$1" end="$2"
        if grep -qF "$begin" "$config_file"; then
            # Escape the marker for use as a literal sed address
            local esc_begin esc_end
            esc_begin="$(printf '%s' "$begin" | sed 's/[^^]/[&]/g; s/\^/\\^/g')"
            esc_end="$(  printf '%s' "$end"   | sed 's/[^^]/[&]/g; s/\^/\\^/g')"
            sed -i "/${esc_begin}/,/${esc_end}/d" "$config_file"
        fi
    }

    # ─────────────────────────────────────────────────────────────────────────
    # BLOCK 1: Adblock + YouTube helpers
    # ─────────────────────────────────────────────────────────────────────────
    local B1_BEGIN="# >>> qutebrowser adblock + youtube (managed)"
    local B1_END="# <<< qutebrowser adblock + youtube (managed)"
    remove_block "$B1_BEGIN" "$B1_END"

    say "Writing adblock + YouTube block..."
    cat >> "$config_file" <<'EOF'

# >>> qutebrowser adblock + youtube (managed)

# Load autoconfig so that :set commands and UI settings coexist with this file
config.load_autoconfig()

# ── Adblock ──────────────────────────────────────────────────────────────────
# Requires: python-adblock (pacman)
c.content.blocking.enabled = True
c.content.blocking.method = "both"          # hosts file + ABP lists
c.content.blocking.adblock.lists = [
    "https://easylist.to/easylist/easylist.txt",         # main ad list
    "https://easylist.to/easylist/easyprivacy.txt",      # tracker list
    "https://easylist.to/easylist/fanboy-annoyance.txt", # social widgets etc.
]

# ── YouTube: play in mpv (ad-free via yt-dlp) ───────────────────────────────
# Press M on any YouTube page or video link to open it in mpv.
# mpv uses yt-dlp as its backend — no ads, no tracking, better quality control.
config.bind('M', 'spawn --detach mpv {url}')

# ── YouTube: redirect to piped.video ────────────────────────────────────────
# Press yp to swap the current YouTube URL to its piped.video equivalent.
# piped.video is a privacy-friendly YouTube frontend with no ads.
config.bind('yp', 'spawn --userscript youtube-to-piped')

# <<< qutebrowser adblock + youtube (managed)
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # BLOCK 2: Dark UI + prefer-dark web pages
    # ─────────────────────────────────────────────────────────────────────────
    local B2_BEGIN="# >>> qutebrowser dark UI (managed)"
    local B2_END="# <<< qutebrowser dark UI (managed)"
    remove_block "$B2_BEGIN" "$B2_END"

    say "Writing dark UI block..."
    cat >> "$config_file" <<'EOF'

# >>> qutebrowser dark UI (managed)

# Web pages: respect prefers-color-scheme: dark where sites support it.
# This is NOT force-dark — it will not invert/recolour sites that don't
# natively support dark mode. Force-dark often breaks layouts and colours.
config.set("colors.webpage.preferred_color_scheme", "dark")

# ── UI colour palette — matte/dark, consistent with niri + waybar theme ─────

# Completion popup
c.colors.completion.fg                          = "#d0d0d0"
c.colors.completion.odd.bg                      = "#141414"
c.colors.completion.even.bg                     = "#101010"
c.colors.completion.category.fg                 = "#ffffff"
c.colors.completion.category.bg                 = "#0f0f0f"
c.colors.completion.category.border.top         = "#0f0f0f"
c.colors.completion.category.border.bottom      = "#0f0f0f"
c.colors.completion.item.selected.fg            = "#ffffff"
c.colors.completion.item.selected.bg            = "#2a2a2a"
c.colors.completion.item.selected.border.top    = "#2a2a2a"
c.colors.completion.item.selected.border.bottom = "#2a2a2a"
c.colors.completion.match.fg                    = "#7aa2f7"

# Status bar
c.colors.statusbar.normal.fg  = "#e6e6e6"
c.colors.statusbar.normal.bg  = "#0f0f0f"
c.colors.statusbar.insert.fg  = "#0f0f0f"
c.colors.statusbar.insert.bg  = "#9ece6a"
c.colors.statusbar.command.fg = "#e6e6e6"
c.colors.statusbar.command.bg = "#0f0f0f"
c.colors.statusbar.caret.fg   = "#0f0f0f"
c.colors.statusbar.caret.bg   = "#e0af68"
c.colors.statusbar.private.fg = "#e6e6e6"
c.colors.statusbar.private.bg = "#1a1a1a"

# Tab bar
c.colors.tabs.bar.bg             = "#0b0b0b"
c.colors.tabs.odd.fg             = "#cfcfcf"
c.colors.tabs.odd.bg             = "#121212"
c.colors.tabs.even.fg            = "#cfcfcf"
c.colors.tabs.even.bg            = "#101010"
c.colors.tabs.selected.odd.fg    = "#ffffff"
c.colors.tabs.selected.odd.bg    = "#2a2a2a"
c.colors.tabs.selected.even.fg   = "#ffffff"
c.colors.tabs.selected.even.bg   = "#2a2a2a"

# Hints (follow-mode link labels)
c.colors.hints.fg = "#0f0f0f"
c.colors.hints.bg = "#e0af68"
c.colors.hints.match.fg = "#2a2a2a"

# Context menu
c.colors.contextmenu.menu.fg     = "#d0d0d0"
c.colors.contextmenu.menu.bg     = "#141414"
c.colors.contextmenu.selected.fg = "#ffffff"
c.colors.contextmenu.selected.bg = "#2a2a2a"

# <<< qutebrowser dark UI (managed)
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # BLOCK 3: Privacy + performance
    # ─────────────────────────────────────────────────────────────────────────
    local B3_BEGIN="# >>> qutebrowser privacy + performance (managed)"
    local B3_END="# <<< qutebrowser privacy + performance (managed)"
    remove_block "$B3_BEGIN" "$B3_END"

    say "Writing privacy + performance block..."
    cat >> "$config_file" <<'EOF'

# >>> qutebrowser privacy + performance (managed)

# ── Privacy hardening ────────────────────────────────────────────────────────

# Block third-party cookies — good balance between privacy and compatibility.
# Use "never" for maximum privacy, but expect some sites to break.
c.content.cookies.accept = "no-3rdparty"

# Reduce WebRTC IP leakage risk (effective even without a VPN/proxy)
c.content.webrtc_ip_handling_policy = "disable-non-proxied-udp"

# Disable browser features commonly used for tracking
c.content.geolocation                   = False  # no location sharing
c.content.notifications.enabled        = False  # no push notification prompts
c.content.media.audio_capture          = False  # no microphone by default
c.content.media.video_capture          = False  # no camera by default
c.content.media.audio_video_capture    = False  # no A/V by default

# Referrer: only send referrer when staying on the same domain
c.content.headers.referer = "same-domain"

# Limit canvas fingerprinting.
# Note: set to True per-site if a web app needs canvas (e.g. some games):
#   :set -u example.com content.canvas_reading true
c.content.canvas_reading = False

# ── Performance + comfort ────────────────────────────────────────────────────

# Disk cache (512 MiB). Reduces repeat network requests on revisited pages.
# Unit is KiB: 524288 KiB = 512 MiB
c.content.cache.size = 524288

# Restore tabs from the last session on startup (crash recovery)
c.auto_save.session = True

# Disable autoplay — saves CPU and avoids unwanted sound/video on page load
c.content.autoplay = False

# <<< qutebrowser privacy + performance (managed)
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # youtube-to-piped userscript
    # ─────────────────────────────────────────────────────────────────────────
    local userscript="$userscripts_dir/youtube-to-piped"
    say "Installing userscript: $userscript"
    cat > "$userscript" <<'EOF'
#!/usr/bin/env bash
# youtube-to-piped
# Qutebrowser userscript: redirects the current YouTube URL to piped.video.
#
# Bound to 'yp' in config.py:
#   config.bind('yp', 'spawn --userscript youtube-to-piped')
#
# QUTE_URL is set by qutebrowser when invoking userscripts.
# Writing to QUTE_FIFO sends commands back to the running qutebrowser instance.
echo "open ${QUTE_URL//youtube.com/piped.video}" >> "$QUTE_FIFO"
EOF
    chmod +x "$userscript"
    ok "youtube-to-piped userscript installed"

    # ─────────────────────────────────────────────────────────────────────────
    # Trigger adblock-update (best-effort — may fail in headless/Wayland env)
    # ─────────────────────────────────────────────────────────────────────────
    say "Attempting headless adblock-update (non-fatal if it fails)..."
    if qutebrowser ":adblock-update" ":quit" >/dev/null 2>&1; then
        ok "adblock-update completed"
    else
        warn "Headless adblock-update failed — run ':adblock-update' inside qutebrowser"
    fi

    ok "qutebrowser configured"
}

# =============================================================================
# VERIFY
# Checks that every expected binary and config file is in place.
# Exits with code 1 if hard failures are found, 0 if all is well.
# =============================================================================

phase_verify() {
    local failures=0 warnings=0

    chk_cmd() {
        local cmd="$1" label="${2:-$1}"
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "Command: $label"
        else
            fail "Command NOT FOUND: $label"
            (( failures++ )) || true
        fi
    }

    chk_file() {
        local f="$1" label="${2:-$1}"
        if [[ -f "$f" ]]; then
            ok "File: $label"
        else
            fail "File NOT FOUND: $label"
            (( failures++ )) || true
        fi
    }

    echo ""
    echo "  ════════════════════════════════════════"
    echo "  arch-apps-install — Verify"
    echo "  ════════════════════════════════════════"

    # ── Core CLI tools ────────────────────────────────────────────────────────
    echo ""
    info "── CLI utilities ──────────────────────"
    for cmd in btop htop fastfetch tree rsync fzf rg fd zoxide bat eza yazi lazygit jq; do
        chk_cmd "$cmd"
    done

    # ── Editors ───────────────────────────────────────────────────────────────
    echo ""
    info "── Editors ────────────────────────────"
    chk_cmd nvim "neovim"
    chk_cmd fresh "fresh-editor"

    # ── Media ─────────────────────────────────────────────────────────────────
    echo ""
    info "── Media ──────────────────────────────"
    for cmd in mpv yt-dlp cmus cava playerctl gimp; do
        chk_cmd "$cmd"
    done

    # ── Browsers ──────────────────────────────────────────────────────────────
    echo ""
    info "── Browsers ───────────────────────────"
    chk_cmd qutebrowser
    chk_cmd brave

    # ── File management ───────────────────────────────────────────────────────
    echo ""
    info "── File management ────────────────────"
    for cmd in pcmanfm udiskie yazi; do
        chk_cmd "$cmd"
    done

    # ── qutebrowser config ────────────────────────────────────────────────────
    echo ""
    info "── qutebrowser config ─────────────────"
    local qb_config="$HOME/.config/qutebrowser/config.py"
    local qb_userscript="$HOME/.local/share/qutebrowser/userscripts/youtube-to-piped"
    chk_file "$qb_config"     "config.py"
    chk_file "$qb_userscript" "youtube-to-piped userscript"

    # Check that all three managed blocks are present in config.py
    if [[ -f "$qb_config" ]]; then
        local block ok_count=0
        for block in \
            "qutebrowser adblock + youtube" \
            "qutebrowser dark UI" \
            "qutebrowser privacy + performance"
        do
            if grep -qF "# >>> $block (managed)" "$qb_config"; then
                ok "Config block present: $block"
                (( ok_count++ )) || true
            else
                warn "Config block missing: $block (run install or update)"
                (( warnings++ )) || true
            fi
        done
    fi

    # ── neovim / LazyVim ──────────────────────────────────────────────────────
    echo ""
    info "── Neovim / LazyVim ───────────────────"
    if [[ -d "$HOME/.config/nvim" ]]; then
        ok "~/.config/nvim exists"
        if [[ -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
            ok "LazyVim config present"
        else
            info "~/.config/nvim exists but does not look like LazyVim — custom config"
        fi
    else
        warn "~/.config/nvim missing — LazyVim not bootstrapped"
        (( warnings++ )) || true
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo "  ════════════════════════════════════════"
    if   (( failures == 0 && warnings == 0 )); then
        ok "All checks passed!"
    elif (( failures == 0 )); then
        warn "Passed with $warnings warning(s)"
    else
        fail "FAILED: $failures error(s), $warnings warning(s)"
    fi
    echo "  ════════════════════════════════════════"
    echo ""

    return $(( failures > 0 ? 1 : 0 ))
}

# =============================================================================
# BANNER
# =============================================================================

print_banner() {
    echo ""
    say "════════════════════════════════════════════"
    say "  arch-apps-install — NIRUCON Edition"
    say "  User:     $USER"
    say "  Home:     $HOME"
    say "  Mode:     $MODE"
    say "  Dry-run:  $DRY_RUN"
    say "════════════════════════════════════════════"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_banner

    case "$MODE" in

        # ── install ────────────────────────────────────────────────────────────
        install)
            bootstrap
            install_packages
            bootstrap_lazyvim
            configure_qutebrowser

            echo ""
            say "════════════════════════════════════════════"
            ok  "Install complete!"
            say "  → Start qutebrowser and run: :adblock-update"
            say "  → Open neovim — LazyVim plugins will finish loading"
            say "  → Verify everything: ./arch-apps-install.sh verify"
            say "════════════════════════════════════════════"
            echo ""
            ;;

        # ── update ────────────────────────────────────────────────────────────
        # Re-syncs packages (--needed = noop if already at latest) and
        # re-applies qutebrowser managed blocks. Fully safe to run at any time.
        update)
            bootstrap
            say "Syncing pacman packages (--needed)..."
            run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
            say "Syncing AUR packages (--needed)..."
            run yay -S --needed --noconfirm "${AUR_PKGS[@]}"
            configure_qutebrowser

            echo ""
            ok "Update complete!"
            say "  → qutebrowser config re-applied — restart qutebrowser"
            echo ""
            ;;

        # ── dry-run ───────────────────────────────────────────────────────────
        dry-run)
            bootstrap
            install_packages
            bootstrap_lazyvim
            configure_qutebrowser

            echo ""
            ok "[dry-run] Preview complete — zero changes were made"
            echo ""
            ;;

        # ── verify ────────────────────────────────────────────────────────────
        verify)
            phase_verify
            ;;

    esac
}

main
