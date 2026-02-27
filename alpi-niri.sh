#!/usr/bin/env bash
# =============================================================================
#  alpi-niri.sh — Arch Linux Post Install: NIRUCON Niri/Wayland Edition
#  Author: Nicklas Rudolfsson (nirucon)
#
#  Installs the full niri Wayland stack from https://github.com/nirucon/niri
#  Safe to run on:
#    - A fresh Arch Linux installation (bootstraps git + yay automatically)
#    - An existing Arch with dwm/X11 running (non-destructive, parallel install)
#
#  Modes:
#    install     — full install (packages + dotfiles/configs)
#    update      — git pull repo + sync any new files to config destinations
#    dry-run     — show what would be done, make no changes
#    uninstall   — remove everything installed by this script
#    verify      — check installation status
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
# CONFIG — edit these if your repo URL or preferred paths change
# =============================================================================

readonly NIRI_REPO="https://github.com/nirucon/niri"
readonly NIRI_REPO_DIR="$HOME/.cache/alpi/niri"          # local clone of repo
readonly LOCAL_BIN="$HOME/.local/bin"
readonly STATE_FILE="$HOME/.local/share/alpi-niri/state" # tracks installed files/pkgs
readonly STATE_DIR="$(dirname "$STATE_FILE")"

# =============================================================================
# PACKAGES
# =============================================================================

# Core Wayland / niri stack — all from official Arch repos
PACMAN_PKGS=(
    git
    wayland
    wayland-protocols
    xorg-xwayland
    foot                        # native Wayland terminal
    waybar                      # status bar
    swaylock                    # screen locker
    swayidle                    # idle management daemon
    swaybg                      # wallpaper setter
    slurp                       # region selector (screenshots)
    wl-clipboard                # clipboard (wl-copy / wl-paste)
    mako                        # Wayland notification daemon
    wofi                        # application launcher
    kanshi                      # output/monitor profile management
    xdg-desktop-portal          # base portal (needed by niri)
    xdg-desktop-portal-gnome    # portal backend recommended for niri
    qt5-wayland                 # Qt5 Wayland backend
    qt6-wayland                 # Qt6 Wayland backend
    libinput                    # input device handling
    polkit-gnome                # polkit authentication agent for Wayland
    ttf-dejavu                  # fallback font
    noto-fonts                  # broad unicode coverage
    ttf-nerd-fonts-symbols-mono # icon glyphs used in waybar
    playerctl                   # media player control (used by waybar scripts)
    pipewire                    # modern audio server
    pipewire-alsa               # ALSA compatibility layer
    pipewire-pulse              # PulseAudio compatibility layer
    wireplumber                 # PipeWire session manager
    networkmanager              # network management (service enabled if missing)
    bash-completion             # shell tab completion
)

# niri itself lives in AUR
AUR_PKGS=(
    niri
    ttf-jetbrains-mono-nerd     # preferred monospace font for foot/waybar
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

# Trap to show which line errored (helpful for debugging)
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
  install    Full install: packages (pacman + AUR) + configs from niri repo
  update     Pull latest niri repo + sync any new/changed configs
  dry-run    Preview all actions without making any changes
  uninstall  Remove everything installed by this script
  verify     Check installation status

EXAMPLES:
  ./alpi-niri.sh install
  ./alpi-niri.sh update
  ./alpi-niri.sh dry-run
  ./alpi-niri.sh uninstall
  ./alpi-niri.sh verify
EOF
}

# Validate mode before going further
case "$MODE" in
    install|update|dry-run|uninstall|verify) ;;
    -h|--help|help) usage; exit 0 ;;
    "") usage; die "No mode specified." ;;
    *) usage; die "Unknown mode: $MODE" ;;
esac

DRY_RUN=0
[[ "$MODE" == "dry-run" ]] && DRY_RUN=1

# =============================================================================
# GUARDS
# =============================================================================

# Never run as root — we use sudo internally where needed
[[ ${EUID:-$(id -u)} -ne 0 ]] || die "Do not run as root. Run as your normal user with sudo rights."

# =============================================================================
# HELPERS
# =============================================================================

# run: execute a command, or just print it in dry-run mode
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        "$@"
    fi
}

# run_sh: like run but via bash -c (for pipes, redirects, etc.)
run_sh() {
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] $*"
    else
        bash -c "$*"
    fi
}

# ensure_dir: create directory (and parents) if missing
ensure_dir() {
    [[ $DRY_RUN -eq 1 ]] && { say "[dry-run] mkdir -p $*"; return; }
    mkdir -p "$@"
}

# state_add: record a file path or package name in the state file
# category is "file" or "pkg" — used by uninstall to know what to remove
state_add() {
    local category="$1" value="$2"
    [[ $DRY_RUN -eq 1 ]] && return
    mkdir -p "$STATE_DIR"
    # Only add if not already present
    grep -qxF "${category}:${value}" "$STATE_FILE" 2>/dev/null || \
        echo "${category}:${value}" >> "$STATE_FILE"
}

# state_list: list all state entries of a given category
state_list() {
    local category="$1"
    [[ -f "$STATE_FILE" ]] || return 0
    grep "^${category}:" "$STATE_FILE" | sed "s|^${category}:||"
}

# state_remove_entry: remove a specific entry from state file
state_remove_entry() {
    local category="$1" value="$2"
    [[ -f "$STATE_FILE" ]] || return
    local escaped
    escaped=$(printf '%s\n' "${category}:${value}" | sed 's/[[\.*^$()+?{}|]/\\&/g')
    sed -i "/^${escaped}$/d" "$STATE_FILE"
}

# git_sync: clone repo if missing, or pull if already cloned
git_sync() {
    local url="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        say "Updating repo: $dir"
        run git -C "$dir" fetch --all --prune
        run git -C "$dir" pull --ff-only || warn "git pull failed — keeping existing tree"
    else
        say "Cloning repo: $url → $dir"
        run git clone "$url" "$dir"
    fi
}

# symlink_file: create a symlink dst → src, backing up dst if it already exists
# Records the symlink in state for uninstall
symlink_file() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || { warn "Source not found, skipping: $src"; return 0; }

    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] symlink $src → $dst"
        return
    fi

    mkdir -p "$(dirname "$dst")"

    # If dst exists and is not already a symlink to src, back it up
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        local backup="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
        warn "Backing up existing file: $dst → $backup"
        mv "$dst" "$backup"
    elif [[ -L "$dst" ]]; then
        # Symlink exists — remove it so we can re-point it
        rm "$dst"
    fi

    ln -s "$src" "$dst"
    ok "Symlinked: $dst → $src"
    state_add "file" "$dst"
}

# symlink_dir_contents: symlink all files inside src_dir into dst_dir
# Handles subdirectories recursively
symlink_dir_contents() {
    local src_dir="$1" dst_dir="$2"
    [[ -d "$src_dir" ]] || { warn "Source dir not found, skipping: $src_dir"; return 0; }

    local f rel dst
    while IFS= read -r -d '' f; do
        rel="${f#$src_dir/}"         # relative path within src_dir
        dst="${dst_dir}/${rel}"
        symlink_file "$f" "$dst"
    done < <(find "$src_dir" -type f -print0)
}

# =============================================================================
# BOOTSTRAP: ensure git and yay are present before anything else
# =============================================================================

bootstrap() {
    step "Bootstrap: ensuring git and yay are available"

    # git is needed to clone our repo and build yay
    if ! command -v git >/dev/null 2>&1; then
        say "git not found — installing via pacman..."
        run sudo pacman -Sy --needed --noconfirm git
    else
        info "git: $(command -v git)"
    fi

    # base-devel is needed to build AUR packages
    if ! pacman -Qq base-devel >/dev/null 2>&1; then
        say "base-devel not found — installing..."
        run sudo pacman -S --needed --noconfirm base-devel
    else
        info "base-devel: already installed"
    fi

    # yay is our AUR helper — build from AUR if missing
    if ! command -v yay >/dev/null 2>&1; then
        say "yay not found — building from AUR..."
        local tmp
        tmp="$(mktemp -d)"
        run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
        rm -rf "$tmp"
        ok "yay installed"
    else
        info "yay: $(command -v yay)"
    fi
}

# =============================================================================
# PACKAGES: install pacman and AUR packages
# =============================================================================

install_packages() {
    step "Installing packages"

    say "Installing ${#PACMAN_PKGS[@]} pacman packages..."
    run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

    # Record all pacman packages in state
    for pkg in "${PACMAN_PKGS[@]}"; do
        state_add "pkg" "$pkg"
    done

    say "Installing ${#AUR_PKGS[@]} AUR packages..."
    run yay -S --needed --noconfirm "${AUR_PKGS[@]}"

    for pkg in "${AUR_PKGS[@]}"; do
        state_add "pkg" "$pkg"
    done

    ok "Packages installed"
}

# =============================================================================
# SERVICES: enable essential systemd services
# =============================================================================

enable_services() {
    step "Enabling services"

    # NetworkManager — only enable if not already active
    # (important: don't disturb an existing network setup on a dwm machine)
    if ! systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
        say "Enabling NetworkManager..."
        run sudo systemctl enable --now NetworkManager
    else
        info "NetworkManager already enabled"
    fi

    ok "Services configured"
}

# =============================================================================
# DOTFILES / CONFIGS: sync from niri repo using symlinks
#
# Repo layout → destination mapping:
#   repo/niri/config.kdl            → ~/.config/niri/config.kdl
#   repo/foot/foot.ini              → ~/.config/foot/foot.ini
#   repo/waybar/config              → ~/.config/waybar/config
#   repo/waybar/style.css           → ~/.config/waybar/style.css
#   repo/waybar/scripts/*.sh        → ~/.config/waybar/scripts/
#   repo/wofi/style.css             → ~/.config/wofi/style.css
#   repo/environment.d/10-theme.conf→ ~/.config/environment.d/10-theme.conf
#   repo/local/bin/*                → ~/.local/bin/   (auto-discovers all files)
# =============================================================================

deploy_configs() {
    step "Deploying configs and scripts from niri repo"

    local repo="$NIRI_REPO_DIR"

    # niri config
    symlink_file "$repo/niri/config.kdl"              "$HOME/.config/niri/config.kdl"

    # foot terminal config
    symlink_file "$repo/foot/foot.ini"                "$HOME/.config/foot/foot.ini"

    # waybar — config, style, and all scripts
    symlink_file "$repo/waybar/config"                "$HOME/.config/waybar/config"
    symlink_file "$repo/waybar/style.css"             "$HOME/.config/waybar/style.css"
    symlink_dir_contents "$repo/waybar/scripts"       "$HOME/.config/waybar/scripts"

    # wofi launcher style
    symlink_file "$repo/wofi/style.css"               "$HOME/.config/wofi/style.css"

    # environment.d — Wayland environment variables loaded by systemd user session
    symlink_dir_contents "$repo/environment.d"        "$HOME/.config/environment.d"

    # local/bin — auto-discover ALL files in repo's local/bin
    # This means adding a new script to the repo and running 'update' is enough
    ensure_dir "$LOCAL_BIN"
    if [[ -d "$repo/local/bin" ]]; then
        local f
        for f in "$repo/local/bin/"*; do
            [[ -f "$f" ]] || continue
            local dst="$LOCAL_BIN/$(basename "$f")"
            symlink_file "$f" "$dst"
            # Ensure scripts are executable even through the symlink
            [[ $DRY_RUN -eq 1 ]] || chmod +x "$f"
        done
    else
        warn "local/bin not found in repo — skipping"
    fi

    ok "Configs deployed"
}

# =============================================================================
# BASH_PROFILE: session selector and Wayland environment exports
#
# Strategy for coexistence with dwm:
#   - If an ALPI-NIRI block already exists → replace it (idempotent update)
#   - If an existing dwm/startx selector exists (not managed by us) → warn + skip
#     The user can add niri to it manually, we won't break their setup
#   - If ~/.bash_profile has no session selector at all → add niri-only selector
#   - On a clean system with no ~/.bash_profile → create it with niri selector
# =============================================================================

configure_bash_profile() {
    step "Configuring ~/.bash_profile"

    local profile="$HOME/.bash_profile"

    # Create profile if it doesn't exist at all
    [[ $DRY_RUN -eq 1 ]] || { [[ -f "$profile" ]] || touch "$profile"; }

    # ── Wayland environment exports ──────────────────────────────────────────
    # These are safe to add alongside any X11 setup — they only affect
    # Wayland sessions and are ignored when running X11
    say "Adding Wayland environment exports to ~/.bash_profile..."
    local -A wayland_exports=(
        [XDG_SESSION_TYPE]="wayland"
        [MOZ_ENABLE_WAYLAND]="1"
        [QT_QPA_PLATFORM]="wayland"
        [ELECTRON_OZONE_PLATFORM_HINT]="wayland"
    )

    for key in "${!wayland_exports[@]}"; do
        local val="${wayland_exports[$key]}"
        local line="export ${key}=${val}"
        if [[ $DRY_RUN -eq 1 ]]; then
            say "[dry-run] Would add to ~/.bash_profile: $line"
        else
            grep -qxF "$line" "$profile" || echo "$line" >> "$profile"
        fi
    done

    # Ensure ~/.local/bin is in PATH
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    if [[ $DRY_RUN -eq 1 ]]; then
        say "[dry-run] Would add to ~/.bash_profile: $path_line"
    else
        grep -qxF "$path_line" "$profile" || echo "$path_line" >> "$profile"
    fi

    # ── Session selector ─────────────────────────────────────────────────────

    # Check if we already own the selector block
    local has_our_block=0
    grep -qF "# >>> ALPI-NIRI SESSION SELECTOR" "$profile" 2>/dev/null && has_our_block=1

    # Check for an existing dwm/startx selector NOT managed by us
    # We look for startx being called outside our own block
    local has_foreign_selector=0
    if [[ $has_our_block -eq 0 ]]; then
        # Temporarily strip our block (it's absent anyway) and check for startx
        grep -qE '(startx|exec startx)' "$profile" 2>/dev/null && has_foreign_selector=1
    fi

    if [[ $has_foreign_selector -eq 1 ]]; then
        warn "Detected existing session selector (startx/dwm) in ~/.bash_profile."
        warn "Not modifying it to avoid breaking your dwm setup."
        warn "You can start niri manually with: ~/.local/bin/start-niri"
        warn "Or add it as an option in your existing selector."
        return 0
    fi

    # Remove our own block if present (clean re-write for idempotency)
    if [[ $DRY_RUN -eq 0 ]]; then
        sed -i '/# >>> ALPI-NIRI SESSION SELECTOR/,/# <<< ALPI-NIRI SESSION SELECTOR/d' "$profile"
    fi

    say "Writing niri session selector to ~/.bash_profile..."
    if [[ $DRY_RUN -eq 0 ]]; then
        cat >> "$profile" <<'SELECTOR'

# >>> ALPI-NIRI SESSION SELECTOR — managed by alpi-niri.sh
# Automatically starts niri on tty1 login — press Enter or 1 to start, 2 for shell
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │         NIRUCON — niri session           │"
    echo "  ├──────────────────────────────────────────┤"
    echo "  │   1)  niri  ·  Wayland (waybar + foot)  │"
    echo "  │   2)  exit  ·  Shell prompt only         │"
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
# GROUPS: add user to input and video groups (needed for niri input/seat access)
# =============================================================================

configure_groups() {
    step "Configuring user groups"

    local -a needed_groups=(input video seat)
    local g

    for g in "${needed_groups[@]}"; do
        if getent group "$g" >/dev/null 2>&1; then
            if ! id -nG "$USER" | grep -qw "$g"; then
                say "Adding $USER to group: $g"
                run sudo usermod -aG "$g" "$USER"
                warn "Group change for '$g' requires logout/login to take effect"
            else
                info "Already in group: $g"
            fi
        else
            warn "Group '$g' does not exist on this system — skipping"
        fi
    done

    ok "Groups configured"
}

# =============================================================================
# VERIFY: check all expected pieces are in place
# =============================================================================

phase_verify() {
    local failures=0 warnings=0

    chk_cmd() {
        local cmd="$1" label="${2:-$1}"
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "Command: $label"
        else
            fail "Command NOT FOUND: $label"; ((failures++)) || true
        fi
    }

    chk_file() {
        local f="$1" label="${2:-$1}"
        if [[ -f "$f" || -L "$f" ]]; then
            # Check that symlinks aren't broken
            if [[ -L "$f" ]] && [[ ! -e "$f" ]]; then
                fail "Broken symlink: $label"; ((failures++)) || true
            else
                ok "File: $label"
            fi
        else
            fail "File NOT FOUND: $label"; ((failures++)) || true
        fi
    }

    chk_svc() {
        local svc="$1"
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            ok "Service enabled: $svc"
        else
            warn "Service not enabled: $svc"; ((warnings++)) || true
        fi
    }

    chk_group() {
        local g="$1"
        if id -nG "$USER" | grep -qw "$g"; then
            ok "Group: $g"
        else
            warn "Not in group: $g"; ((warnings++)) || true
        fi
    }

    echo ""
    echo "  ════════════════════════════════════════"
    echo "  alpi-niri — Verify Installation"
    echo "  ════════════════════════════════════════"

    echo ""
    info "── Core commands ──────────────────────"
    for cmd in niri waybar foot swaylock swayidle swaybg slurp mako wofi kanshi playerctl; do
        chk_cmd "$cmd"
    done

    echo ""
    info "── Config files ───────────────────────"
    chk_file "$HOME/.config/niri/config.kdl"              "niri config.kdl"
    chk_file "$HOME/.config/foot/foot.ini"                "foot foot.ini"
    chk_file "$HOME/.config/waybar/config"                "waybar config"
    chk_file "$HOME/.config/waybar/style.css"             "waybar style.css"
    chk_file "$HOME/.config/wofi/style.css"               "wofi style.css"
    chk_file "$HOME/.config/environment.d/10-theme.conf"  "environment.d 10-theme.conf"

    echo ""
    info "── ~/.local/bin scripts ───────────────"
    if [[ -d "$NIRI_REPO_DIR/local/bin" ]]; then
        local f
        for f in "$NIRI_REPO_DIR/local/bin/"*; do
            [[ -f "$f" ]] || continue
            chk_file "$LOCAL_BIN/$(basename "$f")" "$(basename "$f")"
        done
    else
        warn "Repo not cloned yet — cannot check local/bin scripts"
        ((warnings++)) || true
    fi

    echo ""
    info "── Session / profile ──────────────────"
    if grep -qF "ALPI-NIRI SESSION SELECTOR" "$HOME/.bash_profile" 2>/dev/null; then
        ok "Session selector present in ~/.bash_profile"
    elif grep -qE "(startx|exec startx)" "$HOME/.bash_profile" 2>/dev/null; then
        info "Foreign session selector (dwm/startx) present — start niri manually"
    else
        warn "No session selector in ~/.bash_profile"; ((warnings++)) || true
    fi

    echo ""
    info "── Services ───────────────────────────"
    chk_svc NetworkManager

    echo ""
    info "── User groups ────────────────────────"
    for g in input video seat; do
        chk_group "$g"
    done

    echo ""
    info "── State file ─────────────────────────"
    if [[ -f "$STATE_FILE" ]]; then
        local num_files num_pkgs
        num_files=$(grep -c "^file:" "$STATE_FILE" 2>/dev/null || echo 0)
        num_pkgs=$(grep -c "^pkg:"  "$STATE_FILE" 2>/dev/null || echo 0)
        ok "State file: $STATE_FILE ($num_files files, $num_pkgs packages tracked)"
    else
        warn "State file not found: $STATE_FILE"; ((warnings++)) || true
    fi

    echo ""
    echo "  ════════════════════════════════════════"
    if (( failures == 0 && warnings == 0 )); then
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
# UNINSTALL: remove everything tracked in the state file
# =============================================================================

phase_uninstall() {
    step "Uninstalling alpi-niri"

    if [[ ! -f "$STATE_FILE" ]]; then
        warn "State file not found: $STATE_FILE"
        warn "Nothing to uninstall (or state was already cleaned)."
        return 0
    fi

    # ── Remove symlinked config files ────────────────────────────────────────
    say "Removing symlinked config files..."
    while IFS= read -r dst; do
        if [[ -L "$dst" ]]; then
            say "Removing symlink: $dst"
            run rm "$dst"
        elif [[ -e "$dst" ]]; then
            warn "Not a symlink (skipping to be safe): $dst"
        else
            info "Already gone: $dst"
        fi
    done < <(state_list "file")

    # ── Remove session selector from ~/.bash_profile ─────────────────────────
    local profile="$HOME/.bash_profile"
    if grep -qF "# >>> ALPI-NIRI SESSION SELECTOR" "$profile" 2>/dev/null; then
        say "Removing session selector from ~/.bash_profile..."
        run_sh "sed -i '/# >>> ALPI-NIRI SESSION SELECTOR/,/# <<< ALPI-NIRI SESSION SELECTOR/d' \"$profile\""
        ok "Session selector removed"
    fi

    # ── Remove Wayland env exports from ~/.bash_profile ──────────────────────
    say "Removing Wayland environment exports from ~/.bash_profile..."
    local lines_to_remove=(
        "export XDG_SESSION_TYPE=wayland"
        "export MOZ_ENABLE_WAYLAND=1"
        "export QT_QPA_PLATFORM=wayland"
        "export ELECTRON_OZONE_PLATFORM_HINT=wayland"
    )
    for line in "${lines_to_remove[@]}"; do
        if [[ $DRY_RUN -eq 0 ]]; then
            local escaped
            escaped=$(printf '%s\n' "$line" | sed 's/[[\.*^$()+?{}|]/\\&/g')
            sed -i "/^${escaped}$/d" "$profile" 2>/dev/null || true
        else
            say "[dry-run] Would remove from ~/.bash_profile: $line"
        fi
    done

    # ── Optionally remove packages ────────────────────────────────────────────
    # We ask before removing packages since some may be used by other things
    echo ""
    warn "The following packages were installed by alpi-niri:"
    state_list "pkg" | while IFS= read -r pkg; do echo "  - $pkg"; done
    echo ""
    read -r -p "  Remove packages too? [y/N]: " _rm_pkgs
    if [[ "$_rm_pkgs" =~ ^[Yy]$ ]]; then
        local pkg_list
        mapfile -t pkg_list < <(state_list "pkg")
        if (( ${#pkg_list[@]} > 0 )); then
            say "Removing ${#pkg_list[@]} packages..."
            run sudo pacman -Rns --noconfirm "${pkg_list[@]}" 2>/dev/null || \
                warn "Some packages could not be removed (may be required by other packages)"
        fi
    else
        info "Packages left in place"
    fi

    # ── Clean up state file ───────────────────────────────────────────────────
    if [[ $DRY_RUN -eq 0 ]]; then
        rm -f "$STATE_FILE"
        # Remove state dir if it's empty
        rmdir "$STATE_DIR" 2>/dev/null || true
    fi

    ok "Uninstall complete"
    info "Repo cache left in place: $NIRI_REPO_DIR"
    info "Remove manually if desired: rm -rf $NIRI_REPO_DIR"
}

# =============================================================================
# PRINT BANNER
# =============================================================================

print_banner() {
    echo ""
    say "════════════════════════════════════════════"
    say "  alpi-niri — NIRUCON Wayland Edition"
    say "  User:    $USER"
    say "  Mode:    $MODE"
    say "  Repo:    $NIRI_REPO"
    say "  Dry-run: $DRY_RUN"
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
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"
            install_packages
            enable_services
            deploy_configs
            configure_bash_profile
            configure_groups

            echo ""
            say "════════════════════════════════════════════"
            ok  "Install complete!"
            say "  → Log out and back in (group changes need fresh login)"
            say "  → Start niri: ~/.local/bin/start-niri"
            say "  → Or just log in on tty1 — the selector will appear"
            say "  → Verify: ./alpi-niri.sh verify"
            say "════════════════════════════════════════════"
            echo ""
            ;;

        # ── update ────────────────────────────────────────────────────────────
        # Pull latest from repo, then re-run config deploy.
        # New scripts added to local/bin in the repo are picked up automatically.
        # Packages: --needed means it's a noop if already installed.
        update)
            bootstrap   # ensure yay is still present (e.g. after reinstall)
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"

            say "Checking packages (--needed, noop if already installed)..."
            run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
            run yay -S --needed --noconfirm "${AUR_PKGS[@]}"

            deploy_configs  # re-syncs all symlinks, adds new ones

            echo ""
            ok "Update complete!"
            say "  → New scripts from local/bin are now in ~/.local/bin"
            say "  → Restart niri or reload waybar if you changed configs"
            echo ""
            ;;

        # ── dry-run ───────────────────────────────────────────────────────────
        dry-run)
            # DRY_RUN=1 is already set — all run/run_sh/symlink_file etc.
            # will just print what they would do
            bootstrap
            git_sync "$NIRI_REPO" "$NIRI_REPO_DIR"
            install_packages
            enable_services
            deploy_configs
            configure_bash_profile
            configure_groups

            echo ""
            ok "[dry-run] Preview complete — no changes were made"
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
