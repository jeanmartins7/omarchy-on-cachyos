#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy on CachyOS - Unified Installer
# Supports Omarchy 4.0 (Quattro) & Omarchy 3.x with automatic version detection
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

# 4. Detect Version Type by checking git branch
VERSION_TYPE="v4" # Default fallback
if [ -d "$OMARCHY_SOURCE_DIR/.git" ]; then
    # Try to get the branch or tag name
    OMARCHY_BRANCH=$(cd "$OMARCHY_SOURCE_DIR" && (git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null) || true)
    
    if [ -z "$OMARCHY_BRANCH" ] || [ "$OMARCHY_BRANCH" = "HEAD" ]; then
        OMARCHY_BRANCH=$(cd "$OMARCHY_SOURCE_DIR" && git describe --tags 2>/dev/null || true)
    fi

    log_info "Detected git branch/tag in Omarchy source: ${BOLD}${OMARCHY_BRANCH}${RESET}"

    if [[ "$OMARCHY_BRANCH" =~ v?4\. ]] || [[ "$OMARCHY_BRANCH" == "main" ]] || [[ "$OMARCHY_BRANCH" == "master" ]]; then
        VERSION_TYPE="v4"
    elif [[ "$OMARCHY_BRANCH" =~ v?3\. ]]; then
        VERSION_TYPE="v3"
    fi
elif [ -f "$OMARCHY_SOURCE_DIR/.omarchy_version" ]; then
    VERSION_TYPE="$(cat "$OMARCHY_SOURCE_DIR/.omarchy_version" | tr -d '[:space:]')"
fi

log_info "Detected Omarchy version track: ${BOLD}${VERSION_TYPE}${RESET}"

# ==============================================================================
# Pre-requisites & Shared setup (Yay, keys, repo)
# ==============================================================================
if ! command -v lspci &> /dev/null; then
    log_info "Installing pciutils..."
    sudo pacman -S --needed --noconfirm pciutils
fi

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
OMARCHY_KEY_ID="F0134EE680CAC571"
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver hkps://keyserver.ubuntu.com 2>/dev/null || \
sudo pacman-key --recv-keys "$OMARCHY_KEY_ID" --keyserver keys.openpgp.org 2>/dev/null || true
sudo pacman-key --lsign-key "$OMARCHY_KEY_ID" 2>/dev/null || true

# Add Omarchy Repo
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
    log_success "Added [omarchy] repository to /etc/pacman.conf"
fi
sudo pacman -Sy

# Clean up SDDM config
if [ -f /etc/sddm.conf ]; then
    log_info "Removing /etc/sddm.conf..."
    sudo cp /etc/sddm.conf /etc/sddm.conf.cachyos.bak 2>/dev/null || true
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

# ==============================================================================
# Installer Logic Path Fork
# ==============================================================================
safe_sed_delete() {
    local pattern="$1"
    local file="$2"
    if [ -f "$file" ]; then
        sed -i "/${pattern}/d" "$file" 2>/dev/null || true
    fi
}

OMARCHY_TARGET_DIR="$HOME/.local/share/omarchy"

if [ "$VERSION_TYPE" = "v4" ]; then
    echo -e "${BOLD}${MAGENTA}"
    echo "   ____  __  ______    ____  ________  __   _   ______ "
    echo "  / __ \/  |/  /   |  / __ \/ ____/ / / /  | | / / / / "
    echo " / / / / /|_/ / /| | / /_/ / /   / /_/ /   | |/ /_  _/ "
    echo "/ /_/ / /  / / ___ |/ _, _/ /___/ __  /    |___/ /_/   "
    echo "\____/_/  /_/_/  |_/_/ |_|\____/_/ /_/                 "
    echo "           --- 4.0 INSTALLER ---                       "
    echo -e "${RESET}"

    log_info "Applying CachyOS compatibility patches to Omarchy 4.0..."

    find "$OMARCHY_SOURCE_DIR" -type f -name "*.packages" | while read -r pkgfile; do
        sed -i '/^tldr$/d' "$pkgfile" 2>/dev/null || true
        sed -i '/^tldr /d' "$pkgfile" 2>/dev/null || true
    done

    safe_sed_delete 'pacman\.sh' "$OMARCHY_SOURCE_DIR/install/preflight/all.sh"
    safe_sed_delete 'pacman\.sh' "$OMARCHY_SOURCE_DIR/install/post-install/all.sh"
    find "$OMARCHY_SOURCE_DIR/install" -type f -name "pacman.sh" -exec truncate -s 0 {} + 2>/dev/null || true

    safe_sed_delete 'plymouth\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"
    safe_sed_delete 'limine-snapper\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"
    safe_sed_delete 'limine\.sh' "$OMARCHY_SOURCE_DIR/install/login/all.sh"

    GPU_NVIDIA=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 || true)
    GPU_AMD=$(lspci -nn -d 1002: | grep -E "VGA|3D" | head -n1 || true)
    GPU_INTEL=$(lspci -nn -d 8086: | grep -E "VGA|3D" | head -n1 || true)

    if [[ -n "$GPU_NVIDIA" ]] && [ -f "$SCRIPT_DIR/nvidia.sh" ]; then
        log_info "NVIDIA GPU detected. Installing modern CachyOS NVIDIA helper..."
        mkdir -p "$OMARCHY_SOURCE_DIR/install/config/hardware"
        cp "$SCRIPT_DIR/nvidia.sh" "$OMARCHY_SOURCE_DIR/install/config/hardware/nvidia.sh"
        chmod +x "$OMARCHY_SOURCE_DIR/install/config/hardware/nvidia.sh"
        bash "$SCRIPT_DIR/nvidia.sh"
    fi

    if [ -f "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" ]; then
        if ! grep -q "wifi.backend=iwd" "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" 2>/dev/null; then
            cat >> "$OMARCHY_SOURCE_DIR/install/config/hardware/network.sh" << 'NETEOF'

sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true
if ! grep -q "wifi.backend=iwd" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  sudo mkdir -p /etc/NetworkManager
  sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << 'NME'

[device]
wifi.backend=iwd
NME
fi
NETEOF
        fi
    fi

    UWSM_ENV_SRC="$OMARCHY_SOURCE_DIR/config/uwsm/env"
    if [ -f "$UWSM_ENV_SRC" ]; then
        if ! grep -q "mise activate fish" "$UWSM_ENV_SRC" 2>/dev/null; then
            cat >> "$UWSM_ENV_SRC" << 'EOF2'

if command -v mise &> /dev/null; then
  if [ "$SHELL" = "/bin/fish" ] || [ "$SHELL" = "/usr/bin/fish" ]; then
    eval "$(mise activate fish | string collect)" 2>/dev/null || true
  else
    eval "$(mise activate bash --shims)" 2>/dev/null || true
  fi
fi
EOF2
        fi
    fi
else
    # Omarchy 3.x
    log_info "Executing compatibility installer for Omarchy 3.x..."
    cd "$OMARCHY_SOURCE_DIR"

    if [ -f "install/omarchy-base.packages" ]; then
        sed -i '/tldr/d' install/omarchy-base.packages 2>/dev/null || true
    fi

    if [ -f "install/preflight/all.sh" ]; then
        sed -i '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d' install/preflight/all.sh 2>/dev/null || true
    fi

    GPU_NVIDIA=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 || true)
    if [[ -n "$GPU_NVIDIA" ]] && [ -f "$SCRIPT_DIR/nvidia.sh" ]; then
        log_info "NVIDIA GPU found. Configuring CachyOS preservation..."
        mkdir -p install/config/hardware
        cp "$SCRIPT_DIR/nvidia.sh" install/config/hardware/nvidia.sh
        chmod +x install/config/hardware/nvidia.sh
        bash "$SCRIPT_DIR/nvidia.sh"
    fi

    if [ -f "install/login/all.sh" ]; then
        sed -i '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d' install/login/all.sh 2>/dev/null || true
        sed -i '/run_logged \$OMARCHY_INSTALL\/login\/limine-snapper\.sh/d' install/login/all.sh 2>/dev/null || true
    fi

    if [ -f "install/post-install/all.sh" ]; then
        sed -i '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d' install/post-install/all.sh 2>/dev/null || true
    fi
fi

# ==============================================================================
# Deploy and Run
# ==============================================================================
log_info "Deploying prepared Omarchy source to $OMARCHY_TARGET_DIR..."
mkdir -p "$OMARCHY_TARGET_DIR"

if command -v rsync &>/dev/null; then
    rsync -a --delete --exclude '.git' "$OMARCHY_SOURCE_DIR/" "$OMARCHY_TARGET_DIR/"
else
    cp -rT "$OMARCHY_SOURCE_DIR" "$OMARCHY_TARGET_DIR"
fi

cd "$OMARCHY_TARGET_DIR"

echo -e ""
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e "${BOLD}       Omarchy ${VERSION_TYPE} on CachyOS Preparation Completed!           ${RESET}"
echo -e "${BOLD}${GREEN}================================================================${RESET}"
echo -e ""
read -r -p "Press [ENTER] to begin the Omarchy installation..."

chmod +x "$OMARCHY_TARGET_DIR/install.sh"
"$OMARCHY_TARGET_DIR/install.sh"

log_success "Omarchy ${VERSION_TYPE} installation script has completed!"
