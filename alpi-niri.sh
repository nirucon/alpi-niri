#!/usr/bin/env bash
# =============================================================================
#  alpi-niri.sh — Arch Linux Post Install: NIRUCON Niri/Wayland Edition
#  Author: Nicklas Rudolfsson (nirucon)
#
#  Installs the full niri Wayland compositor stack from:
#    https://github.com/nirucon/niri
#
#  Safe to run on:
#    - A fresh Arch Linux installation  (bootstraps git + yay automatically)
#    - An existing Arch with dwm/X11    (non-destructive, fully parallel)
#
#  Config mapping — repo dirs symlinked into ~/.config/:
#    repo/niri/          → ~/.config/niri/
#    repo/foot/          → ~/.config/foot/
#    repo/waybar/        → ~/.config/waybar/
#    repo/wofi/          → ~/.config/wofi/
#    repo/mako/          → ~/.config/mako/
#    repo/environment.d/ → ~/.config/environment.d/
#    repo/local/bin/*    → ~/.local/bin/   (all files, auto-discovered)
#
#  Adding a new app config to the repo:
#    1. Create repo/<app>/<configfile>
#    2. Add one line to CONFIG_DIRS in this script
#    3. Run: ./alpi-niri.sh update
#
#  Modes:
#    install    Full install (bootstrap + packages + configs)
#    update     git pull + sync new/changed configs, idempotent
#    dry-run    Preview all actions, make zero changes
#    uninstall  Remove everything this script installed
#    verify     Check installation health
#
#  Usage:
#    ./alpi-niri.sh install
#    ./alpi-niri.sh update
#    ./alpi-niri.sh dry-run
#    ./alpi-niri.sh uninstall
#    ./alpi-niri.sh verify
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# CONFIG — adjust repo URL or local paths here if needed
# =============================================================================

readonly NIRI_REPO="https://github.com/nirucon/niri"

# Local git clone of the niri repo — kept in cache, not edited directly
readonly NIRI_REPO_DIR="$HOME/.cache/alpi/niri"

readonly LOCAL_BIN="$HOME/.local/bin"

# State file records every symlink and package we install.
# Uninstall reads this — nothing is guessed or hardcoded there.
readonly STATE_FILE="$HOME/.local/share/alpi-niri/state"
readonly STATE_DIR="$(dirname "$STATE_FILE")"

# =============================================================================
# CONFIG DIRECTORY MAP
# repo subdir → ~/.config subdir
#
# To add a new app: add one entry here, put files in repo/<key>/, run update.
# All files inside each repo dir are symlinked recursively into ~/.config/<val>/
# =============================================================================

declare -A CONFIG_DIRS=(
    [niri]="niri"
    [foot]="foot"
    [waybar]="waybar"
    [wofi]="wofi"
    [mako]="mako"
    [environment.d]="environment.d"
)

# =============================================================================
# PACKAGES
# =============================================================================

# Official Arch repos — niri Wayland stack
PACMAN_PKGS=(
    git                         # needed to clone repo and build AUR packages
    base-devel                  # needed to build AUR packages (makepkg)
    wayland                     # Wayland display protocol
    wayland-protocols           # Wayland protocol extensions
    xorg-xwayland               # XWayland compatibility for X11 apps
    foot                        # native Wayland terminal emulator
    waybar                      # status bar
    swaylock                    # Wayland screen locker
    swayidle                    # idle management (screensaver/lock trigger)
    swaybg                      # wallpaper setter
    slurp                       # region selector for screenshots
    grim                        # screenshot tool (works with slurp)
    wl-clipboard                # clipboard (wl-copy / wl-paste)
    mako                        # Wayland notification daemon
    wofi                        # application launcher (GTK, Wayland-native)
    kanshi                      # output/monitor profile management
    xdg-desktop-portal          # base portal (screen capture, file picker)
    xdg-desktop-portal-gnome    # portal backend recommended by niri
    qt5-wayland                 # Qt5 Wayland platform plugin
    qt6-wayland                 # Qt6 Wayland platform plugin
    libinput                    # input device management
    polkit-gnome                # polkit agent (needed for privilege prompts)
    ttf-dejavu                  # fallback sans/mono font
    noto-fonts                  # broad unicode/emoji coverage
    ttf-nerd-fonts-symbols-mono # icon glyphs used in waybar
    playerctl                   # MPRIS media player control
    pipewire                    # modern audio server
    pipewire-alsa               # ALSA compat layer for pipewire
    pipewire-pulse              # PulseAudio compat layer for pipewire
    wireplumber                 # pipewire session/policy manager
    networkmanager              # network management daemon
    bash-completion             # tab completion for bash
    brightnessctl               # screen brightness
    wdisplays                   # display settings
)

# AUR packages — niri itself is not yet in the official repos
AUR_PKGS=(
    niri                        # niri scrolling Wayland compositor
    ttf-jetbrains-mono-nerd     # preferred monospace nerd font for foot/waybar
)

# =============================================================================
# COLORS / LOGGING
# =============================================================================

NC="\033[0m"
GRN="\033[1;32m"
RED="\033[1;31m"
YLW="\033[1;33m"
BLU="\033[1;34m"
CYN="\033[1;36m"
MAG="\033[1;35m"

say()  { printf "${BLU}[ALPI]${NC} %s\n" "$*"; }
step() { printf "${MAG}[====]${NC} %s\n" "$*"; }
ok()   { printf "${GRN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
info() { printf "${CYN}[INFO]${NC} %s\n" "$*"; }
die()  { fail "$@"; exit 1; }

# Show line number and command on unexpected errors
trap 'fail "Unexpected error at line $LINENO — command: ${BASH_COMMAND:-?}"' ERR

# =============================================================================
# MODE / FLAGS
# =============================================================================

MODE="${1:-}"

usage() {
    cat <<'EOF'
alpi-niri.sh — NIRUCON Niri/Wayland Installer for Arch Linux

USAGE:
  ./alpi-niri.sh <mode>

MODES:
  install    Full install: bootstrap + packages + configs
  update     Pull latest repo + sync configs (idempotent, safe to repeat)
  dry-run    Preview all actions — no changes made
  uninstall  Remove everything installed by this script
  verify     Check installation health

EXAMPLES:
  ./alpi-niri.sh install
  ./alpi-niri.sh update
  ./alpi-niri.sh dry-run
  ./alpi-niri.sh uninstall
  ./alpi-niri.sh verify
EOF
}

# Reject unknown modes early, before doing anything on the system
case "$MODE" in
    install|update|dry-run|uninstall|verify) ;;
    -h|--help|help) usage; exit 0 ;;
    "") usage; die "No mode specified." ;;
    *) usage; die "Unknown mode: '$MODE'" ;;
esac

DRY_RUN=0
[[ "$MODE" == "dry-run" ]] && DRY_RUN=1

# =============================================================================
# ROOT GUARD
# =============================================================================

# Never run as root — sudo is called internally only where needed.
# Running as root would create files owned by root in $HOME, breaking things.
[[ ${EUID:-$(id -u)} -ne 0 ]] || \
    die "Do not run as root. Run as your normal user (with sudo rights)."

# =============================================================================
# CORE HELPERS
# =============================================================================

# run: execute a command normally, or just print it in dry-run mode.
# All system-modifying calls must go through run() or run_sh().
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        "$@"
    fi
}

# run_sh: like run() but uses bash -c for commands needing shell features
# (pipes, redirects, compound expressions).
run_sh() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        bash -c "$*"
    fi
}

# ensure_dir: create a directory tree if it does not exist.
# In dry-run: prints what would happen, creates nothing.
ensure_dir() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] mkdir -p $*"
    else
        mkdir -p "$@"
    fi
}

# =============================================================================
# STATE FILE HELPERS
# State file format: one entry per line — "category:value"
#   file:/home/user/.config/niri/config.kdl
#   pkg:niri
# =============================================================================

# state_add: record a file path or package in the state file (no duplicates).
state_add() {
    local category="$1" value="$2"
    [[ $DRY_RUN -eq 1 ]] && return   # state is never written in dry-run
    mkdir -p "$STATE_DIR"
    grep -qxF "${category}:${value}" "$STATE_FILE" 2>/dev/null || \
        echo "${category}:${value}" >> "$STATE_FILE"
}

# state_list: print all values for a given category, one per line.
state_list() {
    local category="$1"
    [[ -f "$STATE_FILE" ]] || return 0
    grep "^${category}:" "$STATE_FILE" | sed "s|^${category}:||"
}

# =============================================================================
# GIT HELPER
# =============================================================================

# git_sync: clone the repo if it doesn't exist locally, or pull if it does.
# Uses --ff-only to avoid merge commits; warns instead of aborting on conflict.
git_sync() {
    local url="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        say "Updating repo: $(basename "$dir") ..."
        run git -C "$dir" fetch --all --prune
        run git -C "$dir" pull --ff-only || \
            warn "git pull failed (diverged?) — keeping existing local tree"
    else
        say "Cloning: $url → $dir"
        # Ensure parent directory exists before cloning
        [[ $DRY_RUN -eq 0 ]] && mkdir -p "$(dirname "$dir")"
        run git clone "$url" "$dir"
    fi
}

# =============================================================================
# SYMLINK HELPERS
# =============================================================================

# symlink_file: create a symlink at $dst pointing to $src.
#
# Safety rules:
#   - src must exist — warns and skips if not (missing repo files are non-fatal)
#   - if dst is already the correct symlink → skip (idempotent)
#   - if dst is a real file (not a symlink) → back it up with timestamp first
#   - if dst is a wrong/broken symlink → remove and re-create
#
# Records dst in state file so uninstall knows what to clean up.
symlink_file() {
    local src="$1" dst="$2"

    # Source must exist — a missing file in the repo is a warning, not an abort
    if [[ ! -e "$src" ]]; then
        warn "Source not found in repo — skipping: $src"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] symlink: $dst → $src"
        return
    fi

    # Create parent directories for the destination if needed
    mkdir -p "$(dirname "$dst")"

    # If dst is already the correct symlink — nothing to do
    if [[ -L "$dst" ]] && [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
        info "Already correct: $dst"
        state_add "file" "$dst"
        return
    fi

    # If dst is a real file (not a symlink) — back it up before replacing
    if [[ -f "$dst" && ! -L "$dst" ]]; then
        local backup="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
        warn "Backing up existing file: $dst → $backup"
        mv "$dst" "$backup"
    fi

    # Remove any existing symlink (wrong target or broken)
    [[ -L "$dst" ]] && rm "$dst"

    ln -s "$src" "$dst"
    ok "Symlinked: $dst → $src"
    state_add "file" "$dst"
}

# symlink_dir_contents: symlink every file inside src_dir into dst_dir,
# preserving subdirectory structure.
# Example: src_dir=repo/waybar, dst_dir=~/.config/waybar
#   repo/waybar/config          → ~/.config/waybar/config
#   repo/waybar/scripts/foo.sh  → ~/.config/waybar/scripts/foo.sh
symlink_dir_contents() {
    local src_dir="$1" dst_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        warn "Source dir not found in repo — skipping: $src_dir"
        return 0
    fi

    # find -print0 + read -d '' handles filenames with spaces safely
    local f rel dst
    while IFS= read -r -d '' f; do
        rel="${f#${src_dir}/}"       # path relative to src_dir
        dst="${dst_dir}/${rel}"
        symlink_file "$f" "$dst"
    done < <(find "$src_dir" -type f -print0 | sort -z)
}

# =============================================================================
# BOOTSTRAP
# Ensures git, base-devel, and yay are present before anything else runs.
# This is what makes the script work on a fresh Arch with nothing extra installed.
# =============================================================================

bootstrap() {
    step "Bootstrap: ensuring git, base-devel, and yay are available"

    # Sync pacman databases first — critical on a fresh install where they
    # may never have been synced yet
    say "Syncing pacman databases..."
    run sudo pacman -Sy --noconfirm

    # git is required to clone our repo and to build yay from AUR
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

    # yay is our AUR helper — build it from AUR if not present
    if ! command -v yay >/dev/null 2>&1; then
        say "yay not found — building from AUR..."
        local tmp
        tmp="$(mktemp -d)"
        # Ensure temp dir is cleaned up on exit, success or failure
        # shellcheck disable=SC2064
        trap "rm -rf '$tmp'" RETURN
        run git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
        ok "yay installed"
    else
        info "yay: $(command -v yay)"
    fi
}

# =============================================================================
# PACKAGES
# =============================================================================

install_packages() {
    step "Installing packages"

    say "Installing ${#PACMAN_PKGS[@]} pacman packages (--needed = skip if present)..."
    run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

    # Record every pacman package in state so uninstall knows what we touched
    for pkg in "${PACMAN_PKGS[@]}"; do
        state_add "pkg" "$pkg"
    done

    say "Installing ${#AUR_PKGS[@]} AUR packages via yay..."
    run yay -S --needed --noconfirm "${AUR_PKGS[@]}"

    for pkg in "${AUR_PKGS[@]}"; do
        state_add "pkg" "$pkg"
    done

    ok "Packages done"
}

# =============================================================================
# SERVICES
# Only enables services that are not already enabled.
# Never disrupts services managed by an existing dwm/X11 setup.
# =============================================================================

enable_services() {
    step "Enabling services"

    # NetworkManager: skip if already enabled to avoid disrupting a dwm setup
    # that might be using dhcpcd or iwd instead
    if ! systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
        say "Enabling NetworkManager..."
        run sudo systemctl enable --now NetworkManager
        ok "NetworkManager enabled"
    else
        info "NetworkManager already enabled — leaving as-is"
    fi

    # PipeWire/wireplumber user services start automatically after login
    # when the packages are installed — no explicit systemctl enable needed.

    ok "Services done"
}

# =============================================================================
# CONFIGS / DOTFILES
# Deploy repo configs to ~/.config/ via symlinks.
# CONFIG_DIRS drives the mapping — add new apps there, not here.
# local/bin is auto-discovered: all files in repo/local/bin/ are symlinked.
# =============================================================================

deploy_configs() {
    step "Deploying configs from niri repo"

    local repo="$NIRI_REPO_DIR"

    # ── Config directories ────────────────────────────────────────────────────
    # Iterate CONFIG_DIRS map: repo/<key>/ → ~/.config/<value>/
    # All files in each repo dir are symlinked recursively.
    local repo_dir dst_dir
    for repo_dir in "${!CONFIG_DIRS[@]}"; do
        dst_dir="${CONFIG_DIRS[$repo_dir]}"
        say "Syncing: repo/$repo_dir/ → ~/.config/$dst_dir/"
        symlink_dir_contents "$repo/$repo_dir" "$HOME/.config/$dst_dir"
    done

    # ── local/bin — auto-discover all files in repo/local/bin/ ───────────────
    # No hardcoded filenames here. Adding a new script to the repo and running
    # 'update' is all that is needed to deploy it to ~/.local/bin/.
    ensure_dir "$LOCAL_BIN"

    if [[ -d "$repo/local/bin" ]]; then
        say "Syncing: repo/local/bin/ → ~/.local/bin/"
        local f
        while IFS= read -r -d '' f; do
            local dst="$LOCAL_BIN/$(basename "$f")"
            symlink_file "$f" "$dst"
            # Ensure the repo source file is executable (symlink inherits this)
            [[ $DRY_RUN -eq 0 ]] && chmod +x "$f"
        done < <(find "$repo/local/bin" -maxdepth 1 -type f -print0 | sort -z)
    else
        warn "repo/local/bin not found — skipping local/bin deploy"
    fi

    ok "Configs deployed"
}

# =============================================================================
# BASH_PROFILE
# Adds Wayland environment exports and an optional session selector.
#
# Coexistence strategy (clean Arch vs. existing dwm):
#
#   PATH export:
#     Added only if missing — harmless on both setups.
#
#   Wayland env exports (XDG_SESSION_TYPE, MOZ_ENABLE_WAYLAND etc.):
#     Safe to add alongside any X11 setup — these variables only affect
#     Wayland sessions. X11/dwm sessions read the file but ignore them.
#     Added only if the exact line is not already present.
#
#   Session selector:
#     - If we already own the block (ALPI-NIRI marker) → replace it cleanly
#     - If a foreign startx/dwm selector is found → warn and leave it alone
#       (the user can add niri to their own selector manually)
#     - Otherwise → install our niri-only selector
# =============================================================================

configure_bash_profile() {
    step "Configuring ~/.bash_profile"

    local profile="$HOME/.bash_profile"

    # Create ~/.bash_profile if this is a fresh system with none
    if [[ $DRY_RUN -eq 0 ]]; then
        [[ -f "$profile" ]] || touch "$profile"
    fi

    # ── PATH — ensure ~/.local/bin is reachable ───────────────────────────────
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] Would ensure in ~/.bash_profile: $path_line"
    else
        grep -qxF "$path_line" "$profile" || echo "$path_line" >> "$profile"
        ok "PATH export present"
    fi

    # ── Wayland environment exports ───────────────────────────────────────────
    say "Ensuring Wayland environment exports..."
    local -a wayland_exports=(
        "export XDG_SESSION_TYPE=wayland"
        "export MOZ_ENABLE_WAYLAND=1"
        "export QT_QPA_PLATFORM=wayland"
        "export ELECTRON_OZONE_PLATFORM_HINT=wayland"
        "export GDK_BACKEND=wayland"
        "export SDL_VIDEODRIVER=wayland"
    )
    for line in "${wayland_exports[@]}"; do
        if [[ $DRY_RUN -eq 1 ]]; then
            say "[dry-run] Would add if missing: $line"
        else
            grep -qxF "$line" "$profile" || echo "$line" >> "$profile"
        fi
    done
    [[ $DRY_RUN -eq 0 ]] && ok "Wayland exports present"

    # ── Session selector ──────────────────────────────────────────────────────

    # Check if we already own the selector block
    local has_our_block=0
    grep -qF "# >>> ALPI-NIRI SESSION SELECTOR" "$profile" 2>/dev/null \
        && has_our_block=1

    # Check for a foreign session selector (startx/dwm) that we must not touch.
    # Only relevant when our own block is absent (re-runs are fine).
    local has_foreign_selector=0
    if [[ $has_our_block -eq 0 ]]; then
        if grep -qE '^\s*(exec\s+)?startx\b' "$profile" 2>/dev/null; then
            has_foreign_selector=1
        fi
    fi

    if [[ $has_foreign_selector -eq 1 ]]; then
        warn "Existing startx/dwm session selector found in ~/.bash_profile."
        warn "Not modifying it — your dwm setup is safe and unchanged."
        warn "Start niri manually with: exec ~/.local/bin/start-niri"
        warn "Or add niri as an option in your own selector."
        return 0
    fi

    # Remove our own block before re-writing so the result is always clean
    if [[ $DRY_RUN -eq 0 && $has_our_block -eq 1 ]]; then
        sed -i '/# >>> ALPI-NIRI SESSION SELECTOR/,/# <<< ALPI-NIRI SESSION SELECTOR/d' \
            "$profile"
    fi

    say "Writing niri session selector to ~/.bash_profile..."
    if [[ $DRY_RUN -eq 0 ]]; then
        cat >> "$profile" <<'SELECTOR'

# >>> ALPI-NIRI SESSION SELECTOR — managed by alpi-niri.sh
# Triggers on tty1 login when no display server is already running.
# Press Enter or 1 to launch niri, press 2 to stay at the shell.
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │         NIRUCON — niri session           │"
    echo "  ├──────────────────────────────────────────┤"
    echo "  │   1)  niri  ·  wayland                   │"
    echo "  │   2)  exit  ·  shell prompt only         │"
    echo "  └──────────────────────────────────────────┘"
    echo ""
    read -r -p "  Session [1/2, Enter = niri]: " _niru_ses
    case "$_niru_ses" in
        2) : ;;
        *) exec "$HOME/.local/bin/start-niri" ;;
    esac
    unset _niru_ses
fi
# <<< ALPI-NIRI SESSION SELECTOR
SELECTOR
        ok "Session selector written to ~/.bash_profile"
    else
        say "[dry-run] Would write niri session selector to ~/.bash_profile"
    fi
}

# =============================================================================
# GROUPS
# niri needs the user in input, video, and seat groups for direct device access
# (keyboard, mouse, GPU) when running without a display manager.
# Only adds groups that exist on the system — seat may not be present everywhere.
# Group membership changes require a logout to take effect.
# =============================================================================

configure_groups() {
    step "Configuring user groups"

    local -a needed_groups=(input video seat)
    local g

    for g in "${needed_groups[@]}"; do
        if ! getent group "$g" >/dev/null 2>&1; then
            warn "Group '$g' does not exist on this system — skipping"
            continue
        fi
        if id -nG "$USER" | grep -qw "$g"; then
            info "Already in group: $g"
        else
            say "Adding $USER to group: $g"
            run sudo usermod -aG "$g" "$USER"
            warn "Group '$g' added — requires logout/login to take effect"
        fi
    done

    ok "Groups done"
}

# =============================================================================
# VERIFY
# Checks that every expected piece is present and correctly wired up.
# Exits with code 1 if any hard failures are found.
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
        if [[ -L "$f" ]]; then
            # Symlink exists — verify it isn't broken
            if [[ -e "$f" ]]; then
                ok "File (symlink ok): $label"
            else
                fail "Broken symlink: $label → $(readlink "$f")"
                (( failures++ )) || true
            fi
        elif [[ -f "$f" ]]; then
            ok "File: $label"
        else
            fail "File NOT FOUND: $label"
            (( failures++ )) || true
        fi
    }

    chk_svc() {
        local svc="$1"
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            ok "Service enabled: $svc"
        else
            warn "Service not enabled: $svc"
            (( warnings++ )) || true
        fi
    }

    chk_group() {
        local g="$1"
        if id -nG "$USER" | grep -qw "$g"; then
            ok "Group: $g"
        else
            warn "Not in group: $g (may need logout, or group was just added)"
            (( warnings++ )) || true
        fi
    }

    echo ""
    echo "  ════════════════════════════════════════"
    echo "  alpi-niri — Installation Verify"
    echo "  ════════════════════════════════════════"

    # ── Core commands ─────────────────────────────────────────────────────────
    echo ""
    info "── Core commands ──────────────────────"
    for cmd in niri waybar foot swaylock swayidle swaybg slurp grim mako wofi kanshi playerctl; do
        chk_cmd "$cmd"
    done

    # ── Config files — driven by CONFIG_DIRS map ──────────────────────────────
    # We verify every file that exists in the repo is symlinked correctly.
    echo ""
    info "── Config files ───────────────────────"
    local repo_dir dst_dir
    for repo_dir in "${!CONFIG_DIRS[@]}"; do
        dst_dir="${CONFIG_DIRS[$repo_dir]}"
        if [[ -d "$NIRI_REPO_DIR/$repo_dir" ]]; then
            local f rel
            while IFS= read -r -d '' f; do
                rel="${f#${NIRI_REPO_DIR}/${repo_dir}/}"
                chk_file "$HOME/.config/$dst_dir/$rel" "$dst_dir/$rel"
            done < <(find "$NIRI_REPO_DIR/$repo_dir" -type f -print0 | sort -z)
        else
            warn "Repo dir missing: $repo_dir (run install or update first)"
            (( warnings++ )) || true
        fi
    done

    # ── local/bin scripts ─────────────────────────────────────────────────────
    echo ""
    info "── ~/.local/bin scripts ───────────────"
    if [[ -d "$NIRI_REPO_DIR/local/bin" ]]; then
        local f
        while IFS= read -r -d '' f; do
            chk_file "$LOCAL_BIN/$(basename "$f")" "$(basename "$f")"
        done < <(find "$NIRI_REPO_DIR/local/bin" -maxdepth 1 -type f -print0 | sort -z)
    else
        warn "Repo local/bin missing (run install or update first)"
        (( warnings++ )) || true
    fi

    # ── Session / bash_profile ────────────────────────────────────────────────
    echo ""
    info "── Session / profile ──────────────────"
    if grep -qF "ALPI-NIRI SESSION SELECTOR" "$HOME/.bash_profile" 2>/dev/null; then
        ok "Session selector: present (managed by alpi-niri)"
    elif grep -qE '^\s*(exec\s+)?startx\b' "$HOME/.bash_profile" 2>/dev/null; then
        info "Foreign dwm/startx selector present — start niri with: start-niri"
    else
        warn "No session selector in ~/.bash_profile"
        (( warnings++ )) || true
    fi

    # ── Services ──────────────────────────────────────────────────────────────
    echo ""
    info "── Services ───────────────────────────"
    chk_svc NetworkManager

    # ── User groups ───────────────────────────────────────────────────────────
    echo ""
    info "── User groups ────────────────────────"
    for g in input video seat; do
        chk_group "$g"
    done

    # ── State file ────────────────────────────────────────────────────────────
    echo ""
    info "── State file ─────────────────────────"
    if [[ -f "$STATE_FILE" ]]; then
        local num_files num_pkgs
        num_files=$(grep -c "^file:" "$STATE_FILE" 2>/dev/null || echo 0)
        num_pkgs=$(grep -c  "^pkg:"  "$STATE_FILE" 2>/dev/null || echo 0)
        ok "State: $STATE_FILE ($num_files symlinks, $num_pkgs packages tracked)"
    else
        warn "State file missing: $STATE_FILE"
        (( warnings++ )) || true
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo "  ════════════════════════════════════════"
    if   (( failures == 0 && warnings == 0 )); then
        ok "All checks passed — niri is ready!"
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
# UNINSTALL
# Reads the state file and removes every symlink and optionally every package
# recorded during install/update. Only removes what we created — nothing else.
# =============================================================================

phase_uninstall() {
    step "Uninstalling alpi-niri"

    if [[ ! -f "$STATE_FILE" ]]; then
        warn "State file not found: $STATE_FILE"
        warn "Nothing tracked to uninstall."
        return 0
    fi

    # ── Remove symlinked config and bin files ─────────────────────────────────
    say "Removing symlinks..."
    while IFS= read -r dst; do
        if [[ -L "$dst" ]]; then
            say "Removing symlink: $dst"
            run rm "$dst"
        elif [[ -e "$dst" ]]; then
            # Present but not a symlink — we did not create it this way, skip
            warn "Not a symlink — skipping (safe): $dst"
        else
            info "Already gone: $dst"
        fi
    done < <(state_list "file")

    # Remove empty config directories we would have created
    # rmdir is a no-op if the dir is non-empty — guaranteed safe
    if [[ $DRY_RUN -eq 0 ]]; then
        for dir in \
            "$HOME/.config/waybar/scripts" \
            "$HOME/.config/waybar" \
            "$HOME/.config/niri" \
            "$HOME/.config/foot" \
            "$HOME/.config/wofi" \
            "$HOME/.config/mako" \
            "$HOME/.config/environment.d"
        do
            rmdir "$dir" 2>/dev/null || true
        done
    fi

    # ── Remove our session selector block from ~/.bash_profile ────────────────
    local profile="$HOME/.bash_profile"
    if grep -qF "# >>> ALPI-NIRI SESSION SELECTOR" "$profile" 2>/dev/null; then
        say "Removing session selector from ~/.bash_profile..."
        run_sh "sed -i '/# >>> ALPI-NIRI SESSION SELECTOR/,/# <<< ALPI-NIRI SESSION SELECTOR/d' \"$profile\""
        ok "Session selector removed"
    fi

    # ── Remove Wayland environment exports from ~/.bash_profile ───────────────
    say "Removing Wayland environment exports from ~/.bash_profile..."
    local -a wayland_exports=(
        "export XDG_SESSION_TYPE=wayland"
        "export MOZ_ENABLE_WAYLAND=1"
        "export QT_QPA_PLATFORM=wayland"
        "export ELECTRON_OZONE_PLATFORM_HINT=wayland"
        "export GDK_BACKEND=wayland"
        "export SDL_VIDEODRIVER=wayland"
    )
    for line in "${wayland_exports[@]}"; do
        if [[ $DRY_RUN -eq 0 ]]; then
            local escaped
            escaped=$(printf '%s\n' "$line" | sed 's/[[\.*^$()+?{}|]/\\&/g')
            sed -i "/^${escaped}$/d" "$profile" 2>/dev/null || true
        else
            say "[dry-run] Would remove from ~/.bash_profile: $line"
        fi
    done

    # ── Optionally remove packages ────────────────────────────────────────────
    # Always ask — packages like pipewire may be shared with other applications
    echo ""
    warn "The following packages were installed by alpi-niri:"
    state_list "pkg" | while IFS= read -r pkg; do printf "  - %s\n" "$pkg"; done
    echo ""
    read -r -p "  Remove these packages too? [y/N]: " _rm_pkgs
    if [[ "${_rm_pkgs:-}" =~ ^[Yy]$ ]]; then
        local -a pkg_list
        mapfile -t pkg_list < <(state_list "pkg")
        if (( ${#pkg_list[@]} > 0 )); then
            say "Removing ${#pkg_list[@]} packages..."
            # -Rns: remove package + unique deps + config files
            # Non-fatal: some pkgs may be required by other installed packages
            run sudo pacman -Rns --noconfirm "${pkg_list[@]}" 2>/dev/null || \
                warn "Some packages could not be removed (required by others)"
        fi
    else
        info "Packages left in place"
    fi

    # ── Clean up state file and dir ───────────────────────────────────────────
    if [[ $DRY_RUN -eq 0 ]]; then
        rm -f "$STATE_FILE"
        rmdir "$STATE_DIR" 2>/dev/null || true   # only removes if empty
    fi

    echo ""
    ok "Uninstall complete"
    info "Repo cache preserved at: $NIRI_REPO_DIR"
    info "Remove manually if desired: rm -rf $NIRI_REPO_DIR"
}

# =============================================================================
# BANNER
# =============================================================================

print_banner() {
    echo ""
    say "════════════════════════════════════════════"
    say "  alpi-niri — NIRUCON Wayland Edition"
    say "  User:      $USER"
    say "  Home:      $HOME"
    say "  Mode:      $MODE"
    say "  Repo:      $NIRI_REPO"
    say "  Repo dir:  $NIRI_REPO_DIR"
    say "  Dry-run:   $DRY_RUN"
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
        # Full install from scratch.
        # Safe on a clean Arch and safe alongside an existing dwm setup.
        install)
            bootstrap
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"
            install_packages
            enable_services
            deploy_configs
            configure_bash_profile
            configure_groups

            echo ""
            say "════════════════════════════════════════════"
            ok  "Install complete!"
            say "  → Log out and back in (group changes need a fresh login)"
            say "  → Then log in on tty1 — the session selector will appear"
            say "  → Or start niri directly: ~/.local/bin/start-niri"
            say "  → Verify everything: ./alpi-niri.sh verify"
            say "════════════════════════════════════════════"
            echo ""
            ;;

        # ── update ────────────────────────────────────────────────────────────
        # Pull latest from repo, re-sync all configs, ensure packages present.
        # Fully idempotent: safe to run at any time, as many times as needed.
        # New local/bin scripts are picked up automatically.
        # New config dirs are picked up by adding them to CONFIG_DIRS above.
        update)
            bootstrap   # re-verify yay is present (e.g. after OS reinstall)
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"

            say "Checking packages (--needed = noop if already installed)..."
            run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
            run yay     -S --needed --noconfirm "${AUR_PKGS[@]}"

            deploy_configs   # re-sync all symlinks, pick up new files

            echo ""
            ok "Update complete!"
            say "  → New local/bin scripts are live in ~/.local/bin"
            say "  → Reload waybar or restart niri if configs changed"
            echo ""
            ;;

        # ── dry-run ───────────────────────────────────────────────────────────
        # Full preview of install — nothing written, nothing changed.
        # DRY_RUN=1 is set above; all helpers respect it throughout.
        dry-run)
            bootstrap
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"
            install_packages
            enable_services
            deploy_configs
            configure_bash_profile
            configure_groups

            echo ""
            ok "[dry-run] Preview complete — zero changes were made"
            echo ""
            ;;

        # ── uninstall ─────────────────────────────────────────────────────────
        uninstall)
            phase_uninstall
            ;;

        # ── verify ────────────────────────────────────────────────────────────
        verify)
            phase_verify
            ;;

    esac
}

main
