#!/usr/bin/env bash
set -e

# ==============================================================================
# Omarchy on CachyOS - Repository Fetcher
# Fetches and selects Omarchy versions (v4.x, v3.x, or bleeding edge main)
# ==============================================================================

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

# 1. Resolve canonical directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="${OMARCHY_SOURCE_DIR:-$HOME/omarchy}"
REPO_URL="https://github.com/basecamp/omarchy.git"

log_info "Omarchy target directory: ${CYAN}${TARGET_DIR}${RESET}"

# 2. Fetch available tags from GitHub
log_info "Fetching available tags from ${REPO_URL}..."
ALL_TAGS=($(git ls-remote --tags --refs "$REPO_URL" 2>/dev/null | awk -F/ '{print $3}' | grep -E '^v?[0-9]+\.[0-9]+' | sort -rV || true))

if [ ${#ALL_TAGS[@]} -eq 0 ]; then
    log_warn "Could not fetch tags remotely or network is slow. Falling back to default list."
    ALL_TAGS=("v4.0.0" "v3.8.4" "v3.0.0")
fi

# Filter top 8 tags
TAGS=("${ALL_TAGS[@]:0:8}")

echo -e ""
echo -e "${BOLD}====================================================${RESET}"
echo -e "${BOLD}  Select the Omarchy version to install on CachyOS  ${RESET}"
echo -e "${BOLD}====================================================${RESET}"
echo -e " 1) ${CYAN}Bleeding Edge (main / dev branch - Latest)${RESET}"

INDEX=2
for TAG in "${TAGS[@]}"; do
    if [[ "$TAG" =~ ^v?4\. ]]; then
        echo -e " ${INDEX}) ${GREEN}Omarchy 4.x (Quattro)${RESET} -> ${BOLD}${TAG}${RESET} (Recommended)"
    else
        echo -e " ${INDEX}) Omarchy 3.x -> ${TAG}"
    fi
    INDEX=$((INDEX + 1))
done

echo -e ""
read -r -p "Enter your choice [1-$((INDEX - 1))] (Default: 2): " USER_CHOICE
USER_CHOICE="${USER_CHOICE:-2}"

if [ "$USER_CHOICE" -eq 1 ]; then
    SELECTED_REF="main"
    VERSION_TYPE="v4"
    BRANCH_ARGS="--depth 1 --branch main"
    log_info "Selected: Bleeding Edge (main branch)"
elif [ "$USER_CHOICE" -ge 2 ] && [ "$USER_CHOICE" -lt "$INDEX" ]; then
    SELECTED_REF="${TAGS[$((USER_CHOICE - 2))]}"
    if [[ "$SELECTED_REF" =~ ^v?4\. ]]; then
        VERSION_TYPE="v4"
    else
        VERSION_TYPE="v3"
    fi
    BRANCH_ARGS="--depth 1 --branch $SELECTED_REF"
    log_info "Selected: Stable Tag ${BOLD}${SELECTED_REF}${RESET} (${VERSION_TYPE})"
else
    log_warn "Invalid selection. Defaulting to latest release (${TAGS[0]})."
    SELECTED_REF="${TAGS[0]}"
    VERSION_TYPE="v4"
    BRANCH_ARGS="--depth 1 --branch $SELECTED_REF"
fi

# 3. Clean up or confirm target directory
if [ -d "$TARGET_DIR" ]; then
    echo -e ""
    log_warn "Existing directory found at ${TARGET_DIR}"
    read -r -p "Delete existing source and re-clone? [Y/n]: " RECLONE
    RECLONE="${RECLONE:-Y}"
    if [[ "${RECLONE,,}" =~ ^(y|yes)$ ]]; then
        log_info "Cleaning up previous directory..."
        rm -rf "$TARGET_DIR"
    else
        log_info "Keeping existing directory at $TARGET_DIR."
        echo "$VERSION_TYPE" > "$TARGET_DIR/.omarchy_version" 2>/dev/null || true
        echo "$SELECTED_REF" > "$TARGET_DIR/.omarchy_ref" 2>/dev/null || true
        exit 0
    fi
fi

# 4. Clone Omarchy
log_info "Cloning Omarchy into ${TARGET_DIR}..."
mkdir -p "$(dirname "$TARGET_DIR")"
if ! git -c advice.detachedHead=false clone --quiet $BRANCH_ARGS "$REPO_URL" "$TARGET_DIR"; then
    log_error "Failed to clone repository from $REPO_URL."
    exit 1
fi

# Save metadata for installers
echo "$VERSION_TYPE" > "$TARGET_DIR/.omarchy_version"
echo "$SELECTED_REF" > "$TARGET_DIR/.omarchy_ref"

log_success "Successfully fetched Omarchy (${SELECTED_REF}) into ${TARGET_DIR}"
