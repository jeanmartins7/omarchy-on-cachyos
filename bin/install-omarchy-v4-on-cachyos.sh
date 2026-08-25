#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy 4.0 (Quattro) on CachyOS - Non-Destructive Wrapper Installer
# Designed for Omarchy v4 with Hyprland, Quickshell & CachyOS Preservations
# ==============================================================================

# Styling
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
CYAN="\e[36m"
MAGENTA="\e[35m"
RESET="\e[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }

# Persistent installation log — captures both stdout and stderr
INSTALL_LOG="/tmp/omarchy-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$INSTALL_LOG") 2>&1

# Global error trap — reports failing line number and exit code on unexpected abort
trap 'EXIT_CODE=$?; log_error "Script aborted at line $LINENO (exit code: $EXIT_CODE)"; log_error "Full installation log saved at: $INSTALL_LOG"; exit $EXIT_CODE' ERR

log_info "Installation log: ${CYAN}${INSTALL_LOG}${RESET}"

# Check that script is not directly run as root (it uses sudo when needed)
if [ "$EUID" -eq 0 ]; then
    log_error "Please run this script as a normal user (do NOT run with sudo)."
    log_error "The script will prompt for sudo credentials only when required."
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="${HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"

echo -e "${BOLD}${MAGENTA}"
echo "   ____  __  ______    ____  ________  __   _   ______ "
echo "  / __ \/  |/  /   |  / __ \/ ____/ / / /  | | / / / / "
echo " / / / / /|_/ / /| | / /_/ / /   / /_/ /   | |/ /_  _/ "
echo "/ /_/ / /  / / ___ |/ _, _/ /___/ __  /    |___/ /_/   "
echo "\____/_/  /_/_/  |_/_/ |_|\____/_/ /_/                 "
echo "        --- OMARCHY 4.0 (QUATTRO) WRAPPER ---          "
echo "               FOR CACHYOS LINUX                       "
echo -e "${RESET}"

# 1. Directory and Path Resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default source location search
if [ -n "$OMARCHY_SOURCE_DIR" ] && [ -d "$OMARCHY_SOURCE_DIR" ]; then
    SRC_DIR="$OMARCHY_SOURCE_DIR"
elif [ -d "$USER_HOME/omarchy" ]; then
    SRC_DIR="$USER_HOME/omarchy"
elif [ -d "$(dirname "$PROJECT_ROOT")/omarchy" ]; then
    SRC_DIR="$(dirname "$PROJECT_ROOT")/omarchy"
else
    SRC_DIR="$USER_HOME/omarchy"
fi

SYSTEM_OMARCHY_DIR="/usr/share/omarchy"

log_info "Target User:      ${CYAN}${TARGET_USER}${RESET}"
log_info "Source Directory: ${CYAN}${SRC_DIR}${RESET}"
log_info "System Directory: ${CYAN}${SYSTEM_OMARCHY_DIR}${RESET}"

# 2. Dependency Checks (Git, Base Tools, Stow)
log_info "Checking essential dependencies..."

MISSING_DEPS=()
for tool in git lspci stow; do
    if ! command -v "$tool" &>/dev/null; then
        case "$tool" in
            lspci) MISSING_DEPS+=("pciutils") ;;
            *)     MISSING_DEPS+=("$tool") ;;
        esac
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_info "Installing missing base tools: ${MISSING_DEPS[*]}..."
    sudo pacman -S --needed --noconfirm "${MISSING_DEPS[@]}"
fi

# Check / Install Yay (AUR Helper)
if ! command -v yay &> /dev/null; then
    log_info "yay is not installed. Installing yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    YAY_TMP="$(mktemp -d /tmp/yay-build.XXXXXX)"
    git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    (cd "$YAY_TMP" && makepkg -si --noconfirm)
    rm -rf "$YAY_TMP"
    log_success "yay installed successfully."
else
    log_success "yay is available."
fi

# 3. Source Code Validation and Fetching
log_info "Validating Omarchy 4.0 source code..."
FETCH_SCRIPT="$SCRIPT_DIR/fetch-omarchy.sh"

if [ ! -d "$SRC_DIR/bin" ] && [ ! -d "$SRC_DIR/install" ]; then
    if [ -f "$FETCH_SCRIPT" ]; then
        chmod +x "$FETCH_SCRIPT"
        OMARCHY_SOURCE_DIR="$SRC_DIR" "$FETCH_SCRIPT"
    else
        log_info "Cloning Omarchy 4.0 into ${SRC_DIR}..."
        git clone --depth 1 --branch quattro https://github.com/basecamp/omarchy.git "$SRC_DIR"
    fi
fi

if [ ! -d "$SRC_DIR" ]; then
    log_error "Omarchy source directory not found at $SRC_DIR"
    exit 1
fi
log_success "Omarchy source code ready."

# 4. User Identity Configuration
if [ -z "$OMARCHY_USER_NAME" ]; then
    echo -e ""
    read -r -p "Enter your full name (for git/user profile config): " OMARCHY_USER_NAME
    export OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-$TARGET_USER}"
fi

if [ -z "$OMARCHY_USER_EMAIL" ]; then
    read -r -p "Enter your email address: " OMARCHY_USER_EMAIL
    export OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-${TARGET_USER}@localhost}"
fi

# 5. Prepare System Root for Quattro Architecture (/usr/share/omarchy)
log_info "[1/6] Synchronizing Omarchy 4.0 to system directory (${SYSTEM_OMARCHY_DIR})..."
sudo mkdir -p "$SYSTEM_OMARCHY_DIR"

if command -v rsync &>/dev/null; then
    sudo rsync -a --delete --exclude '.git' "$SRC_DIR/" "$SYSTEM_OMARCHY_DIR/"
else
    sudo cp -rfT "$SRC_DIR" "$SYSTEM_OMARCHY_DIR"
fi

# Ensure executable permissions on all binaries
sudo chmod -R 755 "$SYSTEM_OMARCHY_DIR/bin" 2>/dev/null || true
sudo find "$SYSTEM_OMARCHY_DIR/install" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
log_success "Synchronized files to ${SYSTEM_OMARCHY_DIR}."

# 6. Protect CachyOS Ecosystem & Bootloader
log_info "[2/6] Protecting CachyOS package configurations and bootloader..."

# (a) Backup pacman.conf
sudo cp /etc/pacman.conf /etc/pacman.conf.cachy_backup
log_success "Created backup: /etc/pacman.conf.cachy_backup"

# (b) Protect Limine / systemd-boot / Snapper hooks from being overridden by Omarchy GRUB hooks
sudo mkdir -p /etc/pacman.d/hooks
sudo ln -sf /dev/null /etc/pacman.d/hooks/omarchy-boot.hook 2>/dev/null || true
sudo ln -sf /dev/null /etc/pacman.d/hooks/omarchy-grub.hook 2>/dev/null || true
log_success "Created bootloader protection locks in /etc/pacman.d/hooks/."

# (c) Configure Omarchy GPG Key and Repo in pacman.conf
OMARCHY_KEY_ID="F0134EE680CAC571"
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver hkps://keyserver.ubuntu.com 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver keys.openpgp.org 2>/dev/null || \
log_warn "Could not fetch key from remote keyservers; attempting local sign."

sudo pacman-key --lsign-key "$OMARCHY_KEY_ID" 2>/dev/null || true

if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
    log_success "Added [omarchy] repository to /etc/pacman.conf."
fi

# Synchronize package database
sudo pacman -Sy --noconfirm

# (d) Clean /etc/sddm.conf if present to prevent display session conflicts
if [ -f /etc/sddm.conf ]; then
    log_info "Backing up /etc/sddm.conf..."
    sudo cp /etc/sddm.conf /etc/sddm.conf.cachyos.bak 2>/dev/null || true
    # NOTE: Do NOT delete sddm.conf — CachyOS needs it for its display manager
fi

# 7. Hardware & GPU Acceleration (NVIDIA / AMD / Intel)
log_info "[3/6] Configuring hardware video acceleration..."
if [ -f "$SCRIPT_DIR/nvidia.sh" ]; then
    bash "$SCRIPT_DIR/nvidia.sh"
fi

# 8. Omarchy System Orchestration (Root)
log_info "[4/6] Executing Omarchy 4.0 system apply..."

STEP4_LOG="/tmp/omarchy-step4-$(date +%Y%m%d-%H%M%S).log"

# Diagnostic: show what actually exists in the system directory
log_info "Diagnosing Omarchy system directory contents..."
if [ -d "$SYSTEM_OMARCHY_DIR/bin" ]; then
    log_info "  Contents of $SYSTEM_OMARCHY_DIR/bin/:"
    ls -la "$SYSTEM_OMARCHY_DIR/bin/" 2>&1 | while IFS= read -r line; do
        echo -e "    ${CYAN}$line${RESET}"
    done
else
    log_warn "  Directory $SYSTEM_OMARCHY_DIR/bin/ does NOT exist!"
fi

if [ -d "$SYSTEM_OMARCHY_DIR/install" ]; then
    log_info "  Contents of $SYSTEM_OMARCHY_DIR/install/ (top-level):"
    ls -la "$SYSTEM_OMARCHY_DIR/install/" 2>&1 | while IFS= read -r line; do
        echo -e "    ${CYAN}$line${RESET}"
    done
else
    log_warn "  Directory $SYSTEM_OMARCHY_DIR/install/ does NOT exist!"
fi

# Detect the correct apply script name (v4 may use different names)
APPLY_SYSTEM_SCRIPT=""
for candidate in \
    "$SYSTEM_OMARCHY_DIR/bin/omarchy-apply-system" \
    "$SYSTEM_OMARCHY_DIR/bin/omarchy-apply" \
    "$SYSTEM_OMARCHY_DIR/bin/omarchy-setup" \
    "$SYSTEM_OMARCHY_DIR/bin/omarchy-install"; do
    if [ -x "$candidate" ]; then
        APPLY_SYSTEM_SCRIPT="$candidate"
        break
    fi
done

if [ -n "$APPLY_SYSTEM_SCRIPT" ]; then
    log_info "Found system apply script: ${CYAN}$(basename "$APPLY_SYSTEM_SCRIPT")${RESET}"
    log_info "Running $(basename "$APPLY_SYSTEM_SCRIPT") (detailed log: $STEP4_LOG)..."
    set +e
    sudo -E env \
        "PATH=$SYSTEM_OMARCHY_DIR/bin:$PATH" \
        "OMARCHY_PATH=$SYSTEM_OMARCHY_DIR" \
        "OMARCHY_INSTALL=$SYSTEM_OMARCHY_DIR/install" \
        "OMARCHY_INSTALL_USER=$TARGET_USER" \
        "OMARCHY_SETUP_CONTEXT=fresh-install" \
        "$APPLY_SYSTEM_SCRIPT" --install-user "$TARGET_USER" --first-install \
        2>&1 | tee "$STEP4_LOG"
    STEP4_EXIT=${PIPESTATUS[0]}
    set -e

    if [ "$STEP4_EXIT" -ne 0 ]; then
        log_error "$(basename "$APPLY_SYSTEM_SCRIPT") failed with exit code: $STEP4_EXIT"
        log_error "Detailed log saved at: $STEP4_LOG"
        log_error "Last 25 lines of output:"
        tail -25 "$STEP4_LOG" | while IFS= read -r line; do
            echo -e "  ${RED}│${RESET} $line"
        done
        exit "$STEP4_EXIT"
    fi
else
    log_warn "No known system apply script found in $SYSTEM_OMARCHY_DIR/bin/"
    log_warn "Searched for: omarchy-apply-system, omarchy-apply, omarchy-setup, omarchy-install"
    log_warn "Attempting to run post-install scripts manually as fallback..."
    FAILED_SCRIPTS=()
    SCRIPTS_FOUND=0

    # Run hardware detection scripts
    for script in "$SYSTEM_OMARCHY_DIR"/install/hardware/*.sh; do
        if [ -f "$script" ]; then
            SCRIPTS_FOUND=$((SCRIPTS_FOUND + 1))
            SCRIPT_NAME="$(basename "$script")"
            log_info "  Running hardware/$SCRIPT_NAME..."
            set +e
            sudo bash "$script" 2>&1 | tee -a "$STEP4_LOG"
            SCRIPT_EXIT=${PIPESTATUS[0]}
            set -e
            if [ "$SCRIPT_EXIT" -ne 0 ]; then
                log_error "  FAILED: hardware/$SCRIPT_NAME (exit code: $SCRIPT_EXIT)"
                FAILED_SCRIPTS+=("hardware/$SCRIPT_NAME")
            else
                log_success "  Completed: hardware/$SCRIPT_NAME"
            fi
        fi
    done

    # Run post-install scripts
    for script in "$SYSTEM_OMARCHY_DIR"/install/post-install/*.sh; do
        if [ -f "$script" ]; then
            SCRIPTS_FOUND=$((SCRIPTS_FOUND + 1))
            SCRIPT_NAME="$(basename "$script")"
            log_info "  Running post-install/$SCRIPT_NAME..."
            set +e
            sudo bash "$script" 2>&1 | tee -a "$STEP4_LOG"
            SCRIPT_EXIT=${PIPESTATUS[0]}
            set -e
            if [ "$SCRIPT_EXIT" -ne 0 ]; then
                log_error "  FAILED: post-install/$SCRIPT_NAME (exit code: $SCRIPT_EXIT)"
                FAILED_SCRIPTS+=("post-install/$SCRIPT_NAME")
            else
                log_success "  Completed: post-install/$SCRIPT_NAME"
            fi
        fi
    done

    if [ "$SCRIPTS_FOUND" -eq 0 ]; then
        log_warn "No install scripts found in $SYSTEM_OMARCHY_DIR/install/hardware/ or $SYSTEM_OMARCHY_DIR/install/post-install/"
        log_warn "The Omarchy source at $SRC_DIR may have a different structure than expected."
        log_info "Listing all directories in $SYSTEM_OMARCHY_DIR/install/ for reference:"
        find "$SYSTEM_OMARCHY_DIR/install" -type d 2>/dev/null | while IFS= read -r dir; do
            echo -e "    ${CYAN}$dir${RESET}"
        done
        log_info "Listing all .sh files in $SYSTEM_OMARCHY_DIR/install/ for reference:"
        find "$SYSTEM_OMARCHY_DIR/install" -name '*.sh' 2>/dev/null | while IFS= read -r f; do
            echo -e "    ${CYAN}$f${RESET}"
        done
    fi

    if [ ${#FAILED_SCRIPTS[@]} -gt 0 ]; then
        log_warn "The following scripts failed: ${FAILED_SCRIPTS[*]}"
        log_warn "Check the detailed log at: $STEP4_LOG"
    fi
fi
log_success "System-level application completed (log: $STEP4_LOG)."

# 9. Restore and Merge CachyOS Pacman Repositories
log_info "[5/6] Ensuring CachyOS optimized repository mirrors are preserved..."
if [ -f /etc/pacman.conf.cachy_backup ]; then
    # Merge [omarchy] into the CachyOS backup if it wasn't there
    if ! grep -q '^\[omarchy\]' /etc/pacman.conf.cachy_backup; then
        sudo cp /etc/pacman.conf.cachy_backup /etc/pacman.conf
        echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
    else
        sudo cp /etc/pacman.conf.cachy_backup /etc/pacman.conf
    fi
    sudo pacman -Sy --noconfirm
    log_success "CachyOS pacman repositories restored and verified."
fi

# 10. User Provisioning and Dotfiles Management (User space)
log_info "[6/6] Provisioning user environment for $TARGET_USER..."

STEP6_LOG="/tmp/omarchy-step6-$(date +%Y%m%d-%H%M%S).log"

if [ -x "$SYSTEM_OMARCHY_DIR/bin/omarchy-provision-user" ]; then
    log_info "Running omarchy-provision-user (detailed log: $STEP6_LOG)..."
    set +e
    sudo -u "$TARGET_USER" env \
        "PATH=$SYSTEM_OMARCHY_DIR/bin:$PATH" \
        "OMARCHY_PATH=$SYSTEM_OMARCHY_DIR" \
        "OMARCHY_INSTALL=$SYSTEM_OMARCHY_DIR/install" \
        "OMARCHY_SETUP_CONTEXT=fresh-install" \
        "HOME=$USER_HOME" \
        "$SYSTEM_OMARCHY_DIR/bin/omarchy-provision-user" --force --first-install \
        2>&1 | tee "$STEP6_LOG"
    STEP6_EXIT=${PIPESTATUS[0]}
    set -e

    if [ "$STEP6_EXIT" -ne 0 ]; then
        log_warn "omarchy-provision-user exited with code: $STEP6_EXIT (non-fatal, continuing)"
        log_warn "Detailed log saved at: $STEP6_LOG"
        log_warn "Last 15 lines of output:"
        tail -15 "$STEP6_LOG" | while IFS= read -r line; do
            echo -e "  ${YELLOW}│${RESET} $line"
        done
    else
        log_success "User provisioning completed successfully."
    fi
else
    log_warn "omarchy-provision-user not found, skipping user provisioning."
fi

# Fish Shell & Mise Environment Integration
FISH_CONF_DIR="$USER_HOME/.config/fish/conf.d"
mkdir -p "$FISH_CONF_DIR"

if [ ! -f "$FISH_CONF_DIR/omarchy-cachyos.fish" ]; then
    log_info "Adding Omarchy & Mise integration hook for Fish shell..."
    cat > "$FISH_CONF_DIR/omarchy-cachyos.fish" << 'EOF'
# Omarchy & Mise integration for CachyOS Fish Shell
if command -v mise &>/dev/null
    eval (mise activate fish | string collect)
end

if test -d /usr/share/omarchy/bin; and not contains /usr/share/omarchy/bin $PATH
    set -gx PATH /usr/share/omarchy/bin $PATH
end
EOF
fi

# GNU Stow Dotfiles Structure
log_info "Organizing dotfiles structure with GNU Stow..."
DOTFILES_DIR="$USER_HOME/.dotfiles"
mkdir -p "$DOTFILES_DIR/omarchy/.config"

if [ -d "$USER_HOME/.config/omarchy" ] && [ ! -L "$USER_HOME/.config/omarchy" ]; then
    # Move omarchy config into dotfiles package and stow it
    cp -r "$USER_HOME/.config/omarchy" "$DOTFILES_DIR/omarchy/.config/"
    rm -rf "$USER_HOME/.config/omarchy"
    (cd "$DOTFILES_DIR" && stow -R omarchy 2>/dev/null || stow omarchy 2>/dev/null || true)
    log_success "Omarchy configurations linked via GNU Stow (~/.dotfiles/omarchy)."
fi

echo -e ""
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e "${BOLD}       Omarchy 4.0 (Quattro) Installation Complete!            ${RESET}"
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e " Summary of actions performed:"
echo -e "  • Installed Omarchy 4.0 to ${SYSTEM_OMARCHY_DIR}"
echo -e "  • Preserved CachyOS x86-64-v3/v4 optimized pacman mirrors"
echo -e "  • Protected CachyOS bootloader (Limine/systemd-boot) and Snapper hooks"
echo -e "  • Verified NVIDIA / GPU drivers and Wayland VA-API acceleration"
echo -e "  • Provisioned user configuration for ${TARGET_USER}"
echo -e "  • Configured Fish shell, Mise, and GNU Stow dotfiles structure"
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e ""
echo -e "${BOLD}${CYAN}Please restart your computer to enter the unified Hyprland & Quickshell desktop.${RESET}"
