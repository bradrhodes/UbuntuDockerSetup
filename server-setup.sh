#!/usr/bin/env bash
# =================================================================
# Ubuntu Server Setup Script
# =================================================================
# This script configures an Ubuntu server with Docker and other
# essential components for running containerized applications.
# =================================================================

set -e  # Exit on error

# Source the logging module
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/scripts/logging.sh"

# Main function to set up the server
setup_server() {
  log_section "Ubuntu Server Setup"
  log_info "Starting server configuration..."
  
  # Run the bootstrap script to ensure required tools are installed
  log_subsection "Running Bootstrap"
  if [ -f "$SCRIPT_DIR/bootstrap.sh" ]; then
    bash "$SCRIPT_DIR/bootstrap.sh"
  else
    log_fatal "Bootstrap script not found at $SCRIPT_DIR/bootstrap.sh"
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