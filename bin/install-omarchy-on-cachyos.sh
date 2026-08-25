#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy on CachyOS - Unified Installer Entrypoint
# Supports Omarchy 4.0 (Quattro) & Omarchy 3.x with automatic version dispatch
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

echo -e "${BOLD}${CYAN}"
echo "========================================================"
echo "           OMARCHY ON CACHYOS INSTALLER                 "
echo "========================================================"
echo -e "${RESET}"

# 1. Directory and Path Resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OMARCHY_SOURCE_DIR="${OMARCHY_SOURCE_DIR:-$(dirname "$PROJECT_ROOT")/omarchy}"

# 2. Check Git and core tools
if ! command -v git &> /dev/null; then
    log_error "git is not installed. Installing git..."
    sudo pacman -S --needed --noconfirm git
fi

# 3. Interactive Version Fetching
FETCH_SCRIPT="$SCRIPT_DIR/fetch-omarchy.sh"
if [ -f "$FETCH_SCRIPT" ]; then
    chmod +x "$FETCH_SCRIPT"
    OMARCHY_SOURCE_DIR="$OMARCHY_SOURCE_DIR" "$FETCH_SCRIPT"
else
    log_warn "fetch-omarchy.sh not found. Cloning latest repository..."
    if [ ! -d "$OMARCHY_SOURCE_DIR" ]; then
        git clone --depth 1 https://github.com/basecamp/omarchy.git "$OMARCHY_SOURCE_DIR"
    fi
fi

if [ ! -d "$OMARCHY_SOURCE_DIR" ]; then
    log_error "Failed to fetch Omarchy source at $OMARCHY_SOURCE_DIR"
    exit 1
fi

# 4. Detect Version Type (v4 vs v3)
VERSION_TYPE="v4"
if [ -f "$OMARCHY_SOURCE_DIR/.omarchy_version" ]; then
    VERSION_TYPE="$(cat "$OMARCHY_SOURCE_DIR/.omarchy_version" | tr -d '[:space:]')"
fi

log_info "Detected Omarchy version track: ${BOLD}${VERSION_TYPE}${RESET}"

# If Version 4 is selected, forward directly to the dedicated v4 installer
if [ "$VERSION_TYPE" = "v4" ] && [ -f "$SCRIPT_DIR/install-omarchy-v4-on-cachyos.sh" ]; then
    log_info "Launching Omarchy 4.0 (Quattro) installer..."
    chmod +x "$SCRIPT_DIR/install-omarchy-v4-on-cachyos.sh"
    exec "$SCRIPT_DIR/install-omarchy-v4-on-cachyos.sh"
fi

# ==============================================================================
# Legacy / Omarchy 3.x Fallback Installer Flow
# ==============================================================================

log_info "Executing compatibility installer for Omarchy 3.x..."

# Check / Install Yay
if ! command -v yay &> /dev/null; then
    log_info "Installing yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    YAY_TMP="$(mktemp -d /tmp/yay-build.XXXXXX)"
    git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    (cd "$YAY_TMP" && makepkg -si --noconfirm)
    rm -rf "$YAY_TMP"
    log_success "yay installed successfully."
fi

# Configure Omarchy Signing Key
sudo pacman-key --recv-keys F0134EE680CAC571 2>/dev/null || true
sudo pacman-key --lsign-key F0134EE680CAC571 2>/dev/null || true

# Add Omarchy Repo
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
fi
sudo pacman -Sy

# Clean up SDDM config
if [ -f /etc/sddm.conf ]; then
    log_info "Removing /etc/sddm.conf..."
    sudo rm -f /etc/sddm.conf
fi

# User details prompt
if [ -z "$OMARCHY_USER_NAME" ]; then
    read -r -p "Please enter your username/name: " OMARCHY_USER_NAME
    export OMARCHY_USER_NAME
fi

if [ -z "$OMARCHY_USER_EMAIL" ]; then
    read -r -p "Please enter your email address: " OMARCHY_USER_EMAIL
    export OMARCHY_USER_EMAIL
fi

# Apply Patches to Omarchy 3 Source
cd "$OMARCHY_SOURCE_DIR"

# Remove tldr if present
if [ -f "install/omarchy-base.packages" ]; then
    sed -i '/tldr/d' install/omarchy-base.packages 2>/dev/null || true
fi

# Remove pacman preflight
if [ -f "install/preflight/all.sh" ]; then
    sed -i '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d' install/preflight/all.sh 2>/dev/null || true
fi

# NVIDIA Check
GPU_NVIDIA=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 || true)
if [[ -n "$GPU_NVIDIA" ]] && [ -f "$SCRIPT_DIR/nvidia.sh" ]; then
    log_info "NVIDIA GPU found. Configuring CachyOS preservation..."
    mkdir -p install/config/hardware
    cp "$SCRIPT_DIR/nvidia.sh" install/config/hardware/nvidia.sh
    chmod +x install/config/hardware/nvidia.sh
    bash "$SCRIPT_DIR/nvidia.sh"
fi

# Clean login overrides
if [ -f "install/login/all.sh" ]; then
    sed -i '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d' install/login/all.sh 2>/dev/null || true
    sed -i '/run_logged \$OMARCHY_INSTALL\/login\/limine-snapper\.sh/d' install/login/all.sh 2>/dev/null || true
fi

if [ -f "install/post-install/all.sh" ]; then
    sed -i '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d' install/post-install/all.sh 2>/dev/null || true
fi

# Deploy to ~/.local/share/omarchy
TARGET_DEPLOY="$HOME/.local/share/omarchy"
mkdir -p "$TARGET_DEPLOY"
cp -rT "$OMARCHY_SOURCE_DIR" "$TARGET_DEPLOY"
cd "$TARGET_DEPLOY"

echo -e ""
echo -e "${BOLD}${GREEN}Ready to install Omarchy 3.x on CachyOS!${RESET}"
read -r -p "Press Enter to begin the installation..."

chmod +x install.sh
./install.sh
