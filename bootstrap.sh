#!/usr/bin/env bash
# =================================================================
# Bootstrap Script for Ubuntu Server Setup
# =================================================================
# This script checks for required tools and installs any that are
# missing. It handles essential utilities needed before the main
# server setup can run.
# =================================================================

set -e  # Exit on error

# Source the logging module
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/scripts/logging.sh"

# Required tools - these will be installed or upgraded
REQUIRED_TOOLS=(
  "git"      # Version control
  "curl"     # For downloading files
  "unzip"    # For extracting archives
  "sops"     # Secrets management
  "yq"       # YAML processor
  "age"      # Modern encryption (replaces GPG)
  "vim"      # Text editor
  "wget"     # Download tool
  "less"     # Pager for viewing files
)

# Check if a command exists
check_cmd() {
  if command -v "$1" &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# Setup package manager variables
setup_package_manager() {
  if check_cmd apt-get; then
    PKG_MANAGER="apt-get"
    PKG_INSTALL="apt-get install -y"
    PKG_UPDATE="apt-get update"
    log_info "Detected package manager: apt-get (Ubuntu)"
    return 0
  else
    log_error "This script is designed for Ubuntu servers with apt-get."
    return 1
  fi
}

# Setup sudo if needed
setup_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    log_info "Running as root, no sudo needed"
  elif check_cmd sudo; then
    SUDO="sudo"
    # Verify sudo access
    if ! sudo -v; then
      log_error "You need sudo privileges to install packages."
      return 1
    fi
    log_info "Using sudo for package installation"
  else
    log_error "Neither root access nor sudo available. Cannot install packages."
    return 1
  fi
  return 0
}

# Install or upgrade a tool using apt-get
install_tool() {
  local tool=$1
  
  log_info "Installing or upgrading $tool..."
  
  # Try package manager
  if $SUDO $PKG_INSTALL $tool --only-upgrade; then
    log_success "$tool installed or upgraded successfully via apt-get"
    return 0
  fi
  
  log_error "Failed to install or upgrade $tool"
  return 1
}

# Main function to check and install prerequisites
bootstrap() {
  log_section "Checking Prerequisites"
  
  # Initial check of tools
  local required_missing=0
  
  # Check required tools
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if check_cmd "$tool"; then
      log_success "$tool is already installed"
    else
      log_info "$tool is missing, will install"
      required_missing=$((required_missing + 1))
    fi
  done
  
  # Setup package manager
  log_section "Package Manager Setup"
  if ! setup_package_manager; then
    log_error "Cannot proceed without a supported package manager."
    return 1
  fi
  
  # Setup sudo
  if ! setup_sudo; then
    log_error "Cannot proceed without proper privileges."
    return 1
  fi
  
  # Update package indexes
  log_info "Updating package indexes..."
  $SUDO $PKG_UPDATE
  
  # Install and upgrade all required tools
  log_section "Installing/Upgrading Tools"
  
  local failed=0
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! install_tool "$tool"; then
      failed=$((failed + 1))
    fi
  done
  
  if [ $failed -gt 0 ]; then
    log_error "$failed tool(s) could not be installed or upgraded."
    return 1
  fi
  
  # Final verification
  log_section "Verification"
  local missing=0
  
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if check_cmd "$tool"; then
      log_success "$tool is installed and available"
    else
      log_failure "$tool is still missing"
      missing=$((missing + 1))
    fi
  done
  
  if [ $missing -eq 0 ]; then
    log_success "All required tools are now installed!"
    return 0
  else
    log_error "$missing required tool(s) still missing."
    return 1
  fi
}

# Run the bootstrap process
if bootstrap; then
  log_section "Next Steps"
  log_success "Bootstrap completed successfully!"
  log_info "You can now proceed with the server setup script:"
  log_info "  ./server-setup.sh"
  exit 0
else
  log_section "Action Required"
  log_error "Bootstrap process could not complete successfully."
  log_info "Please install the following tools manually:"
  
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! check_cmd "$tool"; then
      log_info "  - $tool"
    fi
  done
  
  exit 1
fi