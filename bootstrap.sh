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

# Define config file path
PUBLIC_CONFIG="$SCRIPT_DIR/config/public.yml"

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

# Load tool versions from config file
load_tool_versions() {
  # Ensure yq is available for checking
  if ! check_cmd yq && [ -f "/usr/local/bin/yq" ]; then
    # If we've just downloaded yq but it's not in PATH yet
    PATH="/usr/local/bin:$PATH"
  fi
  
  if check_cmd yq && [ -f "$PUBLIC_CONFIG" ]; then
    YQ_VERSION=$(yq e '.tool_versions.yq // "v4.40.5"' "$PUBLIC_CONFIG")
    SOPS_VERSION=$(yq e '.tool_versions.sops // "v3.8.1"' "$PUBLIC_CONFIG")
    log_debug "Loaded tool versions from config - yq: $YQ_VERSION, sops: $SOPS_VERSION"
  else
    # Fallback values if yq isn't available yet or config doesn't exist
    YQ_VERSION="v4.40.5"
    SOPS_VERSION="v3.8.1"
    log_debug "Using default tool versions - yq: $YQ_VERSION, sops: $SOPS_VERSION"
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

# Install or upgrade a tool
install_tool() {
  local tool=$1
  
  log_info "Installing or upgrading $tool..."
  
  # Special cases for tools not in standard repositories
  case "$tool" in
    "yq")
      local needs_install=false
      local current_version=""
      
      if ! check_cmd "yq"; then
        needs_install=true
        log_info "yq not found, will install version $YQ_VERSION"
      else
        # Check installed version
        current_version=$(yq --version 2>&1 | grep -o "v[0-9.]*" | head -1)
        if [ "$current_version" != "$YQ_VERSION" ]; then
          log_info "yq version $current_version is installed, but config specifies $YQ_VERSION"
          read -p "Do you want to upgrade yq to $YQ_VERSION? (y/N) " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            needs_install=true
            log_info "Will upgrade yq to $YQ_VERSION"
          else
            log_info "Keeping existing yq $current_version"
            return 0
          fi
        else
          log_success "yq version $YQ_VERSION is already installed"
          return 0
        fi
      fi
      
      if [ "$needs_install" = true ]; then
        log_info "Installing yq $YQ_VERSION from GitHub releases..."
        $SUDO wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
        $SUDO chmod +x /usr/local/bin/yq
        
        if check_cmd "yq"; then
          log_success "yq installed successfully from GitHub (version $YQ_VERSION)"
          return 0
        else
          log_error "Failed to install yq from GitHub"
          return 1
        fi
      fi
      ;;
      
    "sops")
      local needs_install=false
      local current_version=""
      
      if ! check_cmd "sops"; then
        needs_install=true
        log_info "sops not found, will install version $SOPS_VERSION"
      else
        # Check installed version
        current_version=$(sops --version 2>&1 | grep -o "[0-9][0-9.]*" | head -1)
        current_version="v$current_version"
        if [ "$current_version" != "$SOPS_VERSION" ]; then
          log_info "sops version $current_version is installed, but config specifies $SOPS_VERSION"
          read -p "Do you want to upgrade sops to $SOPS_VERSION? (y/N) " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            needs_install=true
            log_info "Will upgrade sops to $SOPS_VERSION"
          else
            log_info "Keeping existing sops $current_version"
            return 0
          fi
        else
          log_success "sops version $SOPS_VERSION is already installed"
          return 0
        fi
      fi
      
      if [ "$needs_install" = true ]; then
        log_info "Installing sops $SOPS_VERSION from GitHub releases..."
        $SUDO wget -qO /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
        $SUDO chmod +x /usr/local/bin/sops
        
        if check_cmd "sops"; then
          log_success "sops installed successfully from GitHub (version $SOPS_VERSION)"
          return 0
        else
          log_error "Failed to install sops from GitHub"
          return 1
        fi
      fi
      ;;
      
    *)
      # Default case - use apt-get
      # First check if package exists
      if ! check_cmd "$tool"; then
        # Try to install it
        if $SUDO $PKG_INSTALL $tool; then
          log_success "$tool installed successfully via apt-get"
          return 0
        fi
      else
        # Try to upgrade it
        if $SUDO $PKG_INSTALL $tool --only-upgrade; then
          log_success "$tool upgraded successfully via apt-get"
          return 0
        fi
      fi
      
      log_error "Failed to install or upgrade $tool"
      return 1
      ;;
  esac
}

# Main function to check and install prerequisites
bootstrap() {
  log_section "Checking Prerequisites"
  
  # Initial check of tools
  local required_missing=0
  
  # Load tool versions from config
  load_tool_versions
  
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

# Make all scripts executable
make_scripts_executable() {
  log_section "Making Scripts Executable"
  log_info "Setting executable permissions on all shell scripts..."
  
  # Make all .sh files in the project directory executable
  find "$SCRIPT_DIR" -name "*.sh" -exec $SUDO chmod +x {} \;
  
  log_success "All scripts are now executable"
  
  # Configure git to ignore filemode changes
  if [ -d "$SCRIPT_DIR/.git" ]; then
    log_info "Configuring git to ignore filemode changes..."
    git -C "$SCRIPT_DIR" config --local core.fileMode false
    log_success "Git configured to ignore filemode changes"
  fi
}

# Run the bootstrap process
if bootstrap; then
  # Make scripts executable and configure git
  make_scripts_executable
  
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