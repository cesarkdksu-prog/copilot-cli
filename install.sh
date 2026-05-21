#!/usr/bin/env bash
set -e
set -o pipefail

# GitHub Copilot CLI Installation Script
# Usage: curl -fsSL https://gh.io/copilot-install | bash
#    or: wget -qO- https://gh.io/copilot-install | bash
# Use | sudo bash to run as root and install to /usr/local/bin
# Export PREFIX to install to $PREFIX/bin/ directory (default: /usr/local for
# root, $HOME/.local for non-root), e.g., export PREFIX=$HOME/custom to install
# to $HOME/custom/bin

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions with consistent formatting
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_info "Installing GitHub Copilot CLI..."

# Detect platform
case "$(uname -s || echo "")" in
  Darwin*) PLATFORM="darwin" ;;
  Linux*) PLATFORM="linux" ;;
  *)
    if command -v winget >/dev/null 2>&1; then
      log_info "Windows detected. Installing via winget..."
      winget install GitHub.Copilot
      exit $?
    else
      log_error "Windows detected but winget not found. Please see https://gh.io/install-copilot-readme"
      exit 1
    fi
    ;;
esac

log_info "Detected platform: $PLATFORM"

# Detect architecture
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) 
    log_error "Unsupported architecture $(uname -m)"
    exit 1 
    ;;
esac

log_info "Detected architecture: $ARCH"

# Set up authentication for GitHub requests if GITHUB_TOKEN is available
CURL_AUTH=()
WGET_AUTH=()
GIT_REMOTE="https://github.com/github/copilot-cli"

if [ -n "$GITHUB_TOKEN" ]; then
  log_info "Using GitHub token for authentication"
  CURL_AUTH=(-H "Authorization: token $GITHUB_TOKEN")
  WGET_AUTH=(--header="Authorization: token $GITHUB_TOKEN")
  GIT_REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/github/copilot-cli"
fi

# Determine download URL based on VERSION
if [ "${VERSION}" = "latest" ] || [ -z "$VERSION" ]; then
  DOWNLOAD_URL="https://github.com/github/copilot-cli/releases/latest/download/copilot-${PLATFORM}-${ARCH}.tar.gz"
  CHECKSUMS_URL="https://github.com/github/copilot-cli/releases/latest/download/SHA256SUMS.txt"
  log_info "Using latest release"
elif [ "${VERSION}" = "prerelease" ]; then
  # Get the latest prerelease tag
  if ! command -v git >/dev/null 2>&1; then
    log_error "git is required to install prerelease versions"
    exit 1
  fi
  log_info "Fetching latest prerelease version..."
  VERSION="$(git ls-remote --tags --sort "version:refname" "$GIT_REMOTE" | tail -1 | awk -F/ '{print $NF}')"
  if [ -z "$VERSION" ]; then
    log_error "Could not determine prerelease version"
    exit 1
  fi
  log_info "Latest prerelease version: $VERSION"
  DOWNLOAD_URL="https://github.com/github/copilot-cli/releases/download/${VERSION}/copilot-${PLATFORM}-${ARCH}.tar.gz"
  CHECKSUMS_URL="https://github.com/github/copilot-cli/releases/download/${VERSION}/SHA256SUMS.txt"
else
  # Prefix version with 'v' if not already present
  case "$VERSION" in
    v*) ;;
    *) VERSION="v$VERSION" ;;
  esac
  DOWNLOAD_URL="https://github.com/github/copilot-cli/releases/download/${VERSION}/copilot-${PLATFORM}-${ARCH}.tar.gz"
  CHECKSUMS_URL="https://github.com/github/copilot-cli/releases/download/${VERSION}/SHA256SUMS.txt"
  log_info "Using specified version: $VERSION"
fi

log_info "Downloading from: $DOWNLOAD_URL"

# Download and extract with error handling
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT
TMP_TARBALL="$TMP_DIR/copilot-${PLATFORM}-${ARCH}.tar.gz"

# Download binary with error handling
if command -v curl >/dev/null 2>&1; then
  log_info "Downloading binary using curl..."
  if ! curl -fsSL "${CURL_AUTH[@]}" "$DOWNLOAD_URL" -o "$TMP_TARBALL"; then
    log_error "Failed to download binary from $DOWNLOAD_URL"
    exit 1
  fi
elif command -v wget >/dev/null 2>&1; then
  log_info "Downloading binary using wget..."
  if ! wget -qO "$TMP_TARBALL" "${WGET_AUTH[@]}" "$DOWNLOAD_URL" 2>/dev/null; then
    log_error "Failed to download binary from $DOWNLOAD_URL"
    exit 1
  fi
else
  log_error "Neither curl nor wget found. Please install one of them."
  exit 1
fi

log_success "Binary downloaded successfully"

# Check that the file is a valid tarball before validation
if ! tar -tzf "$TMP_TARBALL" >/dev/null 2>&1; then
  log_error "Downloaded file is not a valid tarball or is corrupted."
  exit 1
fi

# Attempt to download checksums file and validate
TMP_CHECKSUMS="$TMP_DIR/SHA256SUMS.txt"
CHECKSUMS_AVAILABLE=false

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${CURL_AUTH[@]}" "$CHECKSUMS_URL" -o "$TMP_CHECKSUMS" 2>/dev/null && CHECKSUMS_AVAILABLE=true || true
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_CHECKSUMS" "${WGET_AUTH[@]}" "$CHECKSUMS_URL" 2>/dev/null && CHECKSUMS_AVAILABLE=true || true
fi

if [ "$CHECKSUMS_AVAILABLE" = true ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    log_info "Validating checksum using sha256sum..."
    if (cd "$TMP_DIR" && sha256sum -c --ignore-missing SHA256SUMS.txt >/dev/null 2>&1); then
      log_success "Checksum validated"
    else
      log_error "Checksum validation failed."
      exit 1
    fi
  elif command -v shasum >/dev/null 2>&1; then
    log_info "Validating checksum using shasum..."
    if (cd "$TMP_DIR" && shasum -a 256 -c --ignore-missing SHA256SUMS.txt >/dev/null 2>&1); then
      log_success "Checksum validated"
    else
      log_error "Checksum validation failed."
      exit 1
    fi
  else
    log_warn "No sha256sum or shasum found, skipping checksum validation."
  fi
else
  log_warn "Could not download checksums file, skipping checksum validation."
fi

# Determine installation directory based on user privilege
if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
  PREFIX="${PREFIX:-/usr/local}"
  log_info "Running as root, using PREFIX: $PREFIX"
else
  PREFIX="${PREFIX:-$HOME/.local}"
  log_info "Running as non-root, using PREFIX: $PREFIX"
fi

INSTALL_DIR="$PREFIX/bin"

# Ensure installation directory exists with proper error handling
if ! mkdir -p "$INSTALL_DIR"; then
  log_error "Could not create directory $INSTALL_DIR. You may not have write permissions."
  log_error "Try running this script with sudo or set PREFIX to a directory you own"
  log_error "Example: export PREFIX=\$HOME/.local"
  exit 1
fi

log_info "Installation directory: $INSTALL_DIR"

# Install binary and set permissions
if [ -f "$INSTALL_DIR/copilot" ]; then
  log_warn "Replacing copilot binary found at $INSTALL_DIR/copilot"
fi

tar -xz -C "$INSTALL_DIR" -f "$TMP_TARBALL"
chmod +x "$INSTALL_DIR/copilot"
log_success "GitHub Copilot CLI installed to $INSTALL_DIR/copilot"

# Verify the installed binary is executable
if [ ! -x "$INSTALL_DIR/copilot" ]; then
  log_error "Installation verification failed: binary is not executable"
  exit 1
fi

# Check if installed binary is accessible via PATH
if ! command -v copilot >/dev/null 2>&1; then
  echo ""
  log_warn "$INSTALL_DIR is not in your PATH"

  # Detect shell profile file for PATH
  CURRENT_SHELL="$(basename "${SHELL:-/bin/sh}")"
  case "$CURRENT_SHELL" in
    zsh) RC_FILE="${ZDOTDIR:-$HOME}/.zprofile" ;;
    bash)
      if [ -f "$HOME/.bash_profile" ]; then
        RC_FILE="$HOME/.bash_profile"
      elif [ -f "$HOME/.bash_login" ]; then
        RC_FILE="$HOME/.bash_login"
      else
        RC_FILE="$HOME/.profile"
      fi
      ;;
    fish) RC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/copilot.fish" ;;
    *) RC_FILE="$HOME/.profile" ;;
  esac

  PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""
  if [ "$CURRENT_SHELL" = "fish" ]; then
    PATH_LINE="fish_add_path \"$INSTALL_DIR\""
  fi

  # Prompt user to add to shell rc file (only if interactive)
  if [ -t 0 ] || [ -e /dev/tty ]; then
    echo ""
    printf "Would you like to add it to %s? [y/N] " "$RC_FILE"
    if read -r REPLY </dev/tty 2>/dev/null; then
      if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
        mkdir -p "$(dirname "$RC_FILE")"
        echo "$PATH_LINE" >> "$RC_FILE"
        log_success "Added PATH configuration to $RC_FILE"
        echo "  Restart your shell or run: source $RC_FILE"
      fi
    fi
  else
    echo ""
    log_info "To add $INSTALL_DIR to your PATH permanently, add this to $RC_FILE:"
    echo "  $PATH_LINE"
  fi

  echo ""
  log_info "Installation complete! To get started, run:"
  echo "  $PATH_LINE && copilot help"
else
  echo ""
  log_success "Installation complete! Run 'copilot help' to get started."
fi
