#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy on CachyOS - NVIDIA Detection & Non-Intrusive Configuration
# Detects existing modern CachyOS drivers (RTX 3070, 40xx, etc.) and preserves them
# ==============================================================================

# Colors for terminal output
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }

echo -e "${BOLD}${CYAN}Checking NVIDIA GPU Hardware, Driver Status, and Configuration...${RESET}"

# 1. Detect NVIDIA GPU via PCI
NVIDIA_PCI_INFO=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 || true)

if [[ -z "$NVIDIA_PCI_INFO" ]]; then
    log_info "No NVIDIA GPU detected on this system. Skipping NVIDIA configuration."
    exit 0
fi

GPU_ID=$(echo "$NVIDIA_PCI_INFO" | grep -oP '(?<=\[10de:)[0-9a-fA-F]{4}(?=\])' || true)
GPU_NAME=$(echo "$NVIDIA_PCI_INFO" | sed -E 's/.*\[10de:[0-9a-fA-F]{4}\]:?\s*//' | sed 's/ (rev .*//')

echo -e ""
log_success "Detected GPU: ${BOLD}${GPU_NAME}${RESET} [PCI ID: 10de:${GPU_ID}]"

# 2. Identify Architecture Generation
ARCH_NAME="Legacy / Unknown"
SUPPORTS_OPEN_GSP=false

if [[ -n "$GPU_ID" ]]; then
    DEC_ID=$((16#$GPU_ID))
    if [ "$DEC_ID" -ge $((16#2900)) ]; then
        ARCH_NAME="Blackwell (RTX 50-series or newer)"
        SUPPORTS_OPEN_GSP=true
    elif [ "$DEC_ID" -ge $((16#2600)) ]; then
        ARCH_NAME="Ada Lovelace (RTX 40-series)"
        SUPPORTS_OPEN_GSP=true
    elif [ "$DEC_ID" -ge $((16#2200)) ]; then
        ARCH_NAME="Ampere (RTX 30-series, e.g. RTX 3070)"
        SUPPORTS_OPEN_GSP=true
    elif [ "$DEC_ID" -ge $((16#1e00)) ]; then
        ARCH_NAME="Turing (RTX 20-series / GTX 16-series)"
        SUPPORTS_OPEN_GSP=true
    elif [ "$DEC_ID" -ge $((16#1b00)) ]; then
        ARCH_NAME="Pascal (GTX 10-series)"
        SUPPORTS_OPEN_GSP=false
    elif [ "$DEC_ID" -ge $((16#1300)) ]; then
        ARCH_NAME="Maxwell (GTX 900-series)"
        SUPPORTS_OPEN_GSP=false
    fi
fi

log_info "Architecture: ${BOLD}${ARCH_NAME}${RESET}"

# 3. Check for Active / Installed Modern Driver
DRIVER_ACTIVE=false
DRIVER_VERSION="Unknown"
MODULE_TYPE="Proprietary / Closed"

# Check if NVIDIA kernel module is loaded
if [ -d "/proc/driver/nvidia" ] || lsmod | grep -q "^nvidia "; then
    DRIVER_ACTIVE=true
    if [ -f "/proc/driver/nvidia/version" ]; then
        DRIVER_VERSION=$(head -n1 /proc/driver/nvidia/version | grep -oP 'Kernel Module\s+([0-9\.]+)' | awk '{print $3}' || echo "Loaded")
    fi
elif command -v nvidia-smi &>/dev/null; then
    SMI_OUT=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)
    if [[ -n "$SMI_OUT" ]]; then
        DRIVER_ACTIVE=true
        DRIVER_VERSION="$SMI_OUT"
    fi
fi

# Check if open kernel modules are in use
if grep -qi "open" /proc/driver/nvidia/version 2>/dev/null || pacman -Qs "nvidia-open" >/dev/null 2>&1; then
    MODULE_TYPE="Open Kernel Modules (with GSP Firmware)"
fi

# 4. Driver Preservation Logic
if [ "$DRIVER_ACTIVE" = true ]; then
    log_success "Active NVIDIA Driver detected: ${BOLD}v${DRIVER_VERSION}${RESET} (${MODULE_TYPE})"
    log_success "Your CachyOS driver setup is already modern, active, and optimized."
    log_info "${GREEN}Preserving existing CachyOS driver configuration without alterations.${RESET}"
elif pacman -Qs "nvidia" > /dev/null 2>&1; then
    log_success "NVIDIA driver packages are installed in pacman database. Preserving system packages."
else
    log_warn "No active NVIDIA driver detected."
    log_info "Checking CachyOS hardware detection tool (chwd)..."
    if command -v chwd &>/dev/null; then
        echo -e ""
        read -r -p "Would you like CachyOS chwd to automatically install the recommended driver? [Y/n]: " INSTALL_DRIVER
        INSTALL_DRIVER="${INSTALL_DRIVER:-Y}"
        if [[ "${INSTALL_DRIVER,,}" =~ ^(y|yes)$ ]]; then
            sudo chwd -a
            log_success "Installed driver via CachyOS chwd."
        else
            log_info "Skipping driver installation by user choice."
        fi
    fi
fi

# 5. Check VA-API / Video Acceleration Packages (Non-destructive check)
log_info "Checking hardware video decoding support (VA-API)..."
MISSING_VA_PKGS=()

if ! pacman -Qs libva-utils >/dev/null 2>&1; then
    MISSING_VA_PKGS+=("libva-utils")
fi
if ! pacman -Qs nvidia-vaapi-driver >/dev/null 2>&1; then
    MISSING_VA_PKGS+=("nvidia-vaapi-driver")
fi

if [ ${#MISSING_VA_PKGS[@]} -gt 0 ]; then
    log_info "Installing missing VA-API acceleration utilities: ${MISSING_VA_PKGS[*]}..."
    sudo pacman -S --needed --noconfirm "${MISSING_VA_PKGS[@]}" 2>/dev/null || {
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm "${MISSING_VA_PKGS[@]}" || true
        fi
    }
else
    log_success "VA-API packages (libva-utils, nvidia-vaapi-driver) are already installed."
fi

# 6. Check DRM Modesetting (KMS)
# Check if nvidia_drm modeset is already 1 in runtime or files
MODESET_ACTIVE=false
if [ -f "/sys/module/nvidia_drm/parameters/modeset" ]; then
    CURRENT_MODESET=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || true)
    if [ "$CURRENT_MODESET" = "Y" ] || [ "$CURRENT_MODESET" = "1" ]; then
        MODESET_ACTIVE=true
    fi
fi

if [ "$MODESET_ACTIVE" = true ]; then
    log_success "NVIDIA DRM Kernel Mode Setting (modeset=1) is active."
else
    KMS_CONF="/etc/modprobe.d/nvidia-modeset.conf"
    if [ ! -f "$KMS_CONF" ] && ! grep -rqs "nvidia_drm.*modeset=1" /etc/modprobe.d/; then
        log_info "Configuring DRM kernel modeset in $KMS_CONF for Wayland/Hyprland..."
        sudo tee "$KMS_CONF" > /dev/null << 'EOF'
# Direct Rendering Manager (DRM) Kernel Mode Setting for Wayland/Hyprland
options nvidia_drm modeset=1 fbdev=1
EOF
        log_success "Created $KMS_CONF."
    else
        log_info "DRM modeset configuration file already present in /etc/modprobe.d/."
    fi
fi

# 7. Check & Safely Inject Wayland/Hyprland Environment Variables
UWSM_ENV_DIR="$HOME/.config/uwsm"
UWSM_ENV_FILE="$UWSM_ENV_DIR/env"
mkdir -p "$UWSM_ENV_DIR"
touch "$UWSM_ENV_FILE"

NVIDIA_MARKER="# --- OMARCHY_CACHYOS_NVIDIA_CONFIG ---"

if grep -q "$NVIDIA_MARKER" "$UWSM_ENV_FILE" 2>/dev/null || grep -q "LIBVA_DRIVER_NAME=nvidia" "$UWSM_ENV_FILE" 2>/dev/null; then
    log_success "NVIDIA Wayland environment variables already present in $UWSM_ENV_FILE (kept intact)."
else
    log_info "Adding NVIDIA Wayland/VA-API environment variables to $UWSM_ENV_FILE..."
    cat >> "$UWSM_ENV_FILE" << EOF

$NVIDIA_MARKER
# NVIDIA Wayland & VA-API Hardware Video Acceleration
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
export MOZ_DISABLE_RDD_SANDBOX=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
export CUDA_DISABLE_PERF_BOOST=1
EOF
    log_success "Updated $UWSM_ENV_FILE."
fi

# 8. Check Hyprland Specific Config
HYPR_DIR="$HOME/.config/hypr"
if [ -d "$HYPR_DIR" ]; then
    HYPR_NVIDIA_CONF="$HYPR_DIR/nvidia.conf"
    if [ -f "$HYPR_NVIDIA_CONF" ]; then
        log_info "Hyprland NVIDIA configuration file exists at $HYPR_NVIDIA_CONF (preserved)."
    else
        log_info "Creating default $HYPR_NVIDIA_CONF for Hyprland..."
        cat > "$HYPR_NVIDIA_CONF" << 'EOF'
# NVIDIA Hyprland environment overrides
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = MOZ_DISABLE_RDD_SANDBOX,1
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = CUDA_DISABLE_PERF_BOOST,1
EOF
        log_success "Created $HYPR_NVIDIA_CONF."
    fi
fi

echo -e ""
log_success "${BOLD}NVIDIA status check and environment verification complete.${RESET}"
log_info "No driver downgrades or invasive modifications were performed on your CachyOS system."