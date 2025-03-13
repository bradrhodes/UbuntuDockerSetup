#!/usr/bin/env bash
# =================================================================
# Ubuntu Server Setup Script
# =================================================================
# This script configures an Ubuntu server with Docker and other
# essential components for running containerized applications.
# =================================================================

set -e  # Exit on error
set -o pipefail  # Exit if any command in a pipe fails

# Source the logging module
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/scripts/logging.sh"

# Save the root directory path
ROOT_DIR="$SCRIPT_DIR"

# Extend sudo timeout for the duration of the script
extend_sudo_timeout() {
  # Check if sudo is available
  if command -v sudo &> /dev/null; then
    echo "This script requires sudo privileges for some operations."
    echo "You will be prompted for your password once at the beginning."
    echo "Sudo access will be maintained throughout the script."
    
    # Request sudo privileges and keep them alive
    sudo -v
    
    # Keep sudo privileges alive in the background
    (while true; do sudo -v; sleep 60; done) &
    SUDO_KEEPALIVE_PID=$!
    
    # Trap to kill the sudo keep-alive process when the script exits
    trap 'kill $SUDO_KEEPALIVE_PID' EXIT
  fi
}

# Initialize sudo privileges at the beginning
extend_sudo_timeout

# Configuration files
PUBLIC_CONFIG="$SCRIPT_DIR/config/public.yml"
PRIVATE_CONFIG="$SCRIPT_DIR/config/private.yml"

# Check if files exist
if [ ! -f "$PUBLIC_CONFIG" ]; then
  log_fatal "Public configuration file $PUBLIC_CONFIG not found."
fi

if [ ! -f "$PRIVATE_CONFIG" ]; then
  log_fatal "Encrypted private configuration file $PRIVATE_CONFIG not found.
Please run './manage-secrets.sh init' to create one."
fi

# Load the configuration with SOPS decryption
log_section "Loading Configuration"
log_info "Loading configuration with SOPS decryption..."

if ! PRESERVE_SCRIPT_DIR=true source "$SCRIPT_DIR/scripts/load-config.sh" --public "$PUBLIC_CONFIG" --private "$PRIVATE_CONFIG" --sops; then
  log_fatal "Failed to load configuration."
fi

log_success "Configuration loaded successfully"

# Main function to set up the server
setup_server() {
  log_section "Ubuntu Server Setup"
  log_info "Starting server configuration..."
  
  # Run the bootstrap script to ensure required tools are installed
  log_subsection "Running Bootstrap"
  if [ -f "$ROOT_DIR/bootstrap.sh" ]; then
    bash "$ROOT_DIR/bootstrap.sh"
  else
    log_fatal "Bootstrap script not found at $ROOT_DIR/bootstrap.sh"
  fi
  
  # Display information about the configuration
  log_section "Server Configuration"
  log_info "Server user: $SERVER_USER"
  log_info "Home directory: $SERVER_HOME_DIR"
  
  if [ "$NETWORK_MOUNTS_ENABLED" = true ]; then
    log_info "Network mounts: $NETWORK_MOUNTS_COUNT configured"
  else
    log_info "Network mounts: Not configured"
  fi
  
  # Install Docker and Docker Compose
  source "$SCRIPT_DIR/scripts/docker-setup.sh"
  if ! setup_docker; then
    log_error "Docker installation failed. Aborting setup."
    return 1
  fi
  
  # Setup SSH keys if configured
  source "$SCRIPT_DIR/scripts/ssh-setup.sh"
  if ! setup_ssh; then
    log_error "SSH setup failed."
    return 1
  fi
  
  # Setup GitHub SSH access if configured
  source "$SCRIPT_DIR/scripts/github-setup.sh"
  if ! setup_github; then
    log_error "GitHub setup failed."
    return 1
  fi
  
  # Clone or update Docker configuration repository
  source "$SCRIPT_DIR/scripts/docker-repo-setup.sh"
  if ! setup_docker_repo; then
    log_error "Docker repository setup failed."
    return 1
  fi
  
  # Setup network mounts (NFS, etc.)
  source "$SCRIPT_DIR/scripts/network-mounts-setup.sh"
  if ! setup_network_mounts; then
    log_error "Network mounts setup failed."
    log_info "This is non-fatal, continuing with setup..."
    # We don't return 1 here to avoid failing the entire setup if just the mounts fail
  fi
  
  # Additional setup steps will be added here
  log_info "Server setup complete"
  return 0
}

# Run the main setup function
if setup_server; then
  log_section "Setup Complete"
  log_success "Server has been successfully configured!"
  exit 0
else
  log_section "Setup Failed"
  log_error "Server setup could not be completed."
  exit 1
fi