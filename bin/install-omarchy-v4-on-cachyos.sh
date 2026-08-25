#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy 4.0 (Quattro) on CachyOS - Installer Script
# Optimized for Omarchy v4 with Hyprland & Quickshell on CachyOS
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

echo -e "${BOLD}${MAGENTA}"
echo "   ____  __  ______    ____  ________  __   _   ______ "
echo "  / __ \/  |/  /   |  / __ \/ ____/ / / /  | | / / / / "
echo " / / / / /|_/ / /| | / /_/ / /   / /_/ /   | |/ /_  _/ "
echo "/ /_/ / /  / / ___ |/ _, _/ /___/ __  /    |___/ /_/   "
echo "\____/_/  /_/_/  |_/_/ |_|\____/_/ /_/                 "
echo "           --- ON CACHYOS INSTALLER ---                "
echo -e "${RESET}"

# 1. Directory and Path Resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OMARCHY_SOURCE_DIR="${OMARCHY_SOURCE_DIR:-$(dirname "$PROJECT_ROOT")/omarchy}"
OMARCHY_TARGET_DIR="$HOME/.local/share/omarchy"

log_info "Installer directory: ${SCRIPT_DIR}"
log_info "Source directory:    ${OMARCHY_SOURCE_DIR}"
log_info "Target directory:    ${OMARCHY_TARGET_DIR}"

# 2. Dependency Checks
log_info "Verifying required tools..."

if ! command -v git &> /dev/null; then
    log_error "git is not installed. Installing git..."
    sudo pacman -S --needed --noconfirm git
fi

if ! command -v lspci &> /dev/null; then
    log_info "Installing pciutils..."
    sudo pacman -S --needed --noconfirm pciutils
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
    log_success "yay is already available."
fi

# 3. Fetch Omarchy 4.0 Source
log_info "Checking Omarchy source code..."
FETCH_SCRIPT="$SCRIPT_DIR/fetch-omarchy.sh"

if [ -f "$FETCH_SCRIPT" ]; then
    chmod +x "$FETCH_SCRIPT"
    OMARCHY_SOURCE_DIR="$OMARCHY_SOURCE_DIR" "$FETCH_SCRIPT"
else
    log_warn "fetch-omarchy.sh not found. Cloning default repository..."
    if [ -d "$OMARCHY_SOURCE_DIR" ]; then
        log_info "Using existing source at $OMARCHY_SOURCE_DIR"
    else
        git clone --depth 1 https://github.com/basecamp/omarchy.git "$OMARCHY_SOURCE_DIR"
    fi
fi

if [ ! -d "$OMARCHY_SOURCE_DIR" ] || [ ! -f "$OMARCHY_SOURCE_DIR/install.sh" ]; then
    log_error "Failed to locate valid Omarchy source at $OMARCHY_SOURCE_DIR."
    exit 1
fi

# 4. Omarchy Signing Key & Pacman Repository Configuration
log_info "Configuring Omarchy package signing key..."
OMARCHY_KEY_ID="F0134EE680CAC571"

# Try multiple keyservers for reliability
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver hkps://keyserver.ubuntu.com 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver keys.openpgp.org 2>/dev/null || \
log_warn "Could not fetch key from keyservers; attempting local sign if present."

sudo pacman-key --lsign-key "$OMARCHY_KEY_ID" 2>/dev/null || true

log_info "Checking [omarchy] repository in /etc/pacman.conf..."
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
    log_success "Added [omarchy] repository to /etc/pacman.conf"
else
    log_info "[omarchy] repository already configured."
fi

log_info "Synchronizing pacman package databases..."
sudo pacman -Sy

# 5. SDDM & Display Manager Preparation
if [ -f /etc/sddm.conf ]; then
    log_info "Backing up and removing /etc/sddm.conf to avoid session conflicts..."
    sudo cp /etc/sddm.conf /etc/sddm.conf.cachyos.bak 2>/dev/null || true
    sudo rm -f /etc/sddm.conf
fi

# 6. User Identity Prompts (if not set in environment)
if [ -z "$OMARCHY_USER_NAME" ]; then
    echo -e ""
    read -r -p "Enter your full name (for git/user profile config): " OMARCHY_USER_NAME
    export OMARCHY_USER_NAME
fi

if [ -z "$OMARCHY_USER_EMAIL" ]; then
    read -r -p "Enter your email address: " OMARCHY_USER_EMAIL
    export OMARCHY_USER_EMAIL
fi

# 7. Apply CachyOS Optimization Patches to Omarchy Source
log_info "Applying CachyOS compatibility patches to Omarchy 4.0..."

# Helper for safe sed
safe_sed_delete() {
    local pattern="$1"
    local file="$2"
    if [ -f "$file" ]; then
        sed -i "/${pattern}/d" "$file" 2>/dev/null || true
        log_success "Patched: removed '${pattern}' from ${file}"
    fi
}

# (a) Prevent conflict between tldr and CachyOS's tealdeer
find "$OMARCHY_SOURCE_DIR" -type f -name "*.packages" | while read -r pkgfile; do
    sed -i '/^tldr$/d' "$pkgfile" 2>/dev/null || true
    sed -i '/^tldr /d' "$pkgfile" 2>/dev/null || true
done
log_success "Preserved CachyOS tealdeer (removed tldr package references)."

# (b) Neutralize any Omarchy pacman.conf override scripts to preserve CachyOS repo mirrors
safe_sed_delete 'pacman\.sh' "$OMARCHY_SOURCE_DIR/install/preflight/all.sh"
safe_sed_delete 'pacman\.sh' "$OMARCHY_SOURCE_DIR/install/post-install/all.sh"
find "$OMARCHY_SOURCE_DIR/install" -type f -name "pacman.sh" -exec truncate -s 0 {} + 2>/dev/null || true

# (c) Preserve CachyOS bootloader & plymouth configurations
safe_sed_delete 'plymouth\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"
safe_sed_delete 'limine-snapper\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"
safe_sed_delete 'limine\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"

# (d) GPU Hardware Configuration
GPU_NVIDIA=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 || true)
GPU_AMD=$(lspci -nn -d 1002: | grep -E "VGA|3D" | head -n1 || true)
GPU_INTEL=$(lspci -nn -d 8086: | grep -E "VGA|3D" | head -n1 || true)

if [[ -n "$GPU_NVIDIA" ]]; then
    log_info "NVIDIA GPU detected. Installing modern CachyOS NVIDIA helper..."
    if [ -f "$SCRIPT_DIR/nvidia.sh" ]; then
        # Replace or install into Omarchy hardware config location
        mkdir -p "$OMARCHY_SOURCE_DIR/install/config/hardware"
        cp "$SCRIPT_DIR/nvidia.sh" "$OMARCHY_SOURCE_DIR/install/config/hardware/nvidia.sh"
        chmod +x "$OMARCHY_SOURCE_DIR/install/config/hardware/nvidia.sh"
        # Run it directly during setup
        bash "$SCRIPT_DIR/nvidia.sh"
    fi
elif [[ -n "$GPU_AMD" ]]; then
    log_info "AMD GPU detected. CachyOS Mesa/RADV drivers preserved."
elif [[ -n "$GPU_INTEL" ]]; then
    log_info "Intel GPU detected. CachyOS Intel Media drivers preserved."
fi

# (e) NetworkManager & iwd Configuration
if [ -f "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" ]; then
    if ! grep -q "wifi.backend=iwd" "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" 2>/dev/null; then
        cat >> "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" << 'NETEOF'

# CachyOS NetworkManager iwd backend configuration
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true
if ! grep -q "wifi.backend=iwd" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  sudo mkdir -p /etc/NetworkManager
  sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << 'EOF'

[device]
wifi.backend=iwd
EOF
fi
NETEOF
    fi
fi

# (f) Fish Shell & Mise Activation Integration
UWSM_ENV_SRC="$OMARCHY_SOURCE_DIR/config/uwsm/env"
if [ -f "$UWSM_ENV_SRC" ]; then
    if ! grep -q "mise activate fish" "$UWSM_ENV_SRC" 2>/dev/null; then
        cat >> "$UWSM_ENV_SRC" << 'EOF'

# Shell integration for Mise (Bash & Fish)
if command -v mise &> /dev/null; then
  if [ "$SHELL" = "/bin/fish" ] || [ "$SHELL" = "/usr/bin/fish" ]; then
    eval "$(mise activate fish | string collect)" 2>/dev/null || true
  else
    eval "$(mise activate bash --shims)" 2>/dev/null || true
  fi
fi
EOF
    fi
fi

# 8. Deploy to ~/.local/share/omarchy
log_info "Deploying prepared Omarchy 4.0 source to $OMARCHY_TARGET_DIR..."
mkdir -p "$OMARCHY_TARGET_DIR"

# Rsync / copy files cleanly without nested directory bug
if command -v rsync &>/dev/null; then
    rsync -a --delete --exclude '.git' "$OMARCHY_SOURCE_DIR/" "$OMARCHY_TARGET_DIR/"
else
    cp -rT "$OMARCHY_SOURCE_DIR" "$OMARCHY_TARGET_DIR"
fi

cd "$OMARCHY_TARGET_DIR"

# 9. Summary and Confirmation Prompt
echo -e ""
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e "${BOLD}       Omarchy 4.0 on CachyOS Preparation Completed!           ${RESET}"
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e " 1. Configured [omarchy] package repository."
echo -e " 2. Preserved CachyOS tealdeer and CPU-optimized packages."
echo -e " 3. Protected CachyOS pacman mirrors and hardware drivers."
echo -e " 4. Configured NVIDIA / Wayland hardware acceleration."
echo -e " 5. Preserved CachyOS bootloader and Snapper snapshot integration."
echo -e " 6. Configured Fish shell & Mise compatibility."
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e ""
read -r -p "Press [ENTER] to begin the Omarchy 4.0 installation (or Ctrl+C to abort)..."

# 10. Execute Omarchy Installer
chmod +x "$OMARCHY_TARGET_DIR/install.sh"
"$OMARCHY_TARGET_DIR/install.sh"

log_success "Omarchy 4.0 installation script has completed!"
