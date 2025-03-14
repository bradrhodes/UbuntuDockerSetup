#!/usr/bin/env bash
# =================================================================
# Configuration Loader for Ubuntu Server Setup
# =================================================================
# This script loads configuration from public and private YAML files
# and exports variables for use in the main setup script.
# =================================================================

# Source the logging module
if [ -z "$PRESERVE_SCRIPT_DIR" ] || [ "$PRESERVE_SCRIPT_DIR" != "true" ]; then
  # Normal operation - set SCRIPT_DIR to this script's directory
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  ROOT_DIR="$( cd "$SCRIPT_DIR/.." &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
else
  # Preserve the existing SCRIPT_DIR from parent script
  CONFIG_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  # If ROOT_DIR isn't set, derive it
  if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR="$SCRIPT_DIR"
  fi
  source "$CONFIG_SCRIPT_DIR/logging.sh"
fi

# Default config file locations
PUBLIC_CONFIG="$ROOT_DIR/config/public.yml"
PRIVATE_CONFIG="$ROOT_DIR/config/private.yml"
SOPS_ENABLED=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --public)
      PUBLIC_CONFIG="$2"
      shift 2
      ;;
    --private)
      PRIVATE_CONFIG="$2"
      shift 2
      ;;
    --sops)
      SOPS_ENABLED=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      log_info "Usage: $0 [--public PUBLIC_CONFIG] [--private PRIVATE_CONFIG] [--sops]"
      exit 1
      ;;
  esac
done

# Check if the public config file exists
if [ ! -f "$PUBLIC_CONFIG" ]; then
  log_fatal "Public configuration file $PUBLIC_CONFIG not found."
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  log_fatal "yq is required but not installed.\nPlease run bootstrap.sh first to install required tools."
fi

# Load SOPS if enabled
if [ "$SOPS_ENABLED" = true ]; then
  if ! command -v sops &> /dev/null; then
    log_fatal "sops is required for decryption but not installed.\nPlease run bootstrap.sh first to install required tools."
  fi
  
  # Create a temporary file for the decrypted content
  TEMP_PRIVATE_CONFIG=$(mktemp)
  trap 'rm -f "$TEMP_PRIVATE_CONFIG"' EXIT
  
  # Decrypt the private config
  log_info "Decrypting private configuration with SOPS..."
  sops --decrypt "$PRIVATE_CONFIG" > "$TEMP_PRIVATE_CONFIG"
  PRIVATE_CONFIG="$TEMP_PRIVATE_CONFIG"
fi

# Check if the private config file exists (after potential decryption)
if [ ! -f "$PRIVATE_CONFIG" ]; then
  log_fatal "Private configuration file $PRIVATE_CONFIG not found."
fi

# Load configuration into variables
log_section "Loading Configuration"
log_info "Loading configuration from $PUBLIC_CONFIG and $PRIVATE_CONFIG..."

# Core configuration from public config
export SERVER_USER=$(yq '.user // ""' "$PUBLIC_CONFIG")
export SERVER_HOME_DIR=$(yq '.home_dir // ""' "$PUBLIC_CONFIG")

# If user is empty, use current user
if [ -z "$SERVER_USER" ]; then
  export SERVER_USER=$(whoami)
  log_info "User not specified in config, using current user: $SERVER_USER"
fi

# If home_dir is empty, use current user's home directory
if [ -z "$SERVER_HOME_DIR" ]; then
  export SERVER_HOME_DIR=$HOME
  log_info "Home directory not specified in config, using current user's home: $SERVER_HOME_DIR"
fi

# Load logging configuration
log_level_value=$(yq '.log_level // "info"' "$PUBLIC_CONFIG")
case "$log_level_value" in
  debug)
    export LOG_LEVEL=0
    ;;
  info)
    export LOG_LEVEL=1
    ;;
  warn|warning)
    export LOG_LEVEL=2
    ;;
  error)
    export LOG_LEVEL=3
    ;;
  *)
    log_warn "Unknown log level in config: $log_level_value, using 'info'"
    export LOG_LEVEL=1
    ;;
esac

log_debug "Log level set to: $log_level_value ($LOG_LEVEL)"

# Git configuration from private config if available
if yq '.git_user' "$PRIVATE_CONFIG" | grep -q "null"; then
  log_debug "No git_user configuration found in private config"
else
  export GIT_USER_NAME=$(yq '.git_user.name' "$PRIVATE_CONFIG")
  export GIT_USER_EMAIL=$(yq '.git_user.email' "$PRIVATE_CONFIG")
  export GIT_SIGNING_KEY=$(yq '.git_user.signing_key // ""' "$PRIVATE_CONFIG")
  log_debug "Loaded Git configuration for user: $GIT_USER_NAME"
fi

# SSH configuration from private config if available
if yq '.ssh' "$PRIVATE_CONFIG" | grep -q "null"; then
  log_debug "No SSH configuration found in private config"
else
  export SSH_GENERATE_KEY=$(yq '.ssh.generate_key // false' "$PRIVATE_CONFIG")
  export SSH_KEY_TYPE=$(yq '.ssh.key_type // "ed25519"' "$PRIVATE_CONFIG")
  export SSH_KEY_EMAIL=$(yq '.ssh.key_email // ""' "$PRIVATE_CONFIG")
  log_debug "Loaded SSH configuration, generate key: $SSH_GENERATE_KEY"
fi

# GitHub configuration from private config if available
if yq '.github' "$PRIVATE_CONFIG" | grep -q "null"; then
  log_debug "No GitHub configuration found in private config"
else
  # GitHub credentials
  export GITHUB_USERNAME=$(yq '.github.username // ""' "$PRIVATE_CONFIG")
  export GITHUB_ACCESS_TOKEN=$(yq '.github.access_token // ""' "$PRIVATE_CONFIG")
  export GITHUB_UPLOAD_KEY=$(yq '.github.upload_key // false' "$PRIVATE_CONFIG")
  
  if [ "$GITHUB_UPLOAD_KEY" = "true" ]; then
    log_debug "GitHub SSH key upload enabled"
  else
    log_debug "GitHub SSH key upload disabled"
  fi
  
  if [ -n "$GITHUB_USERNAME" ]; then
    log_debug "GitHub username configured: $GITHUB_USERNAME"
  fi
fi

# Docker repo configuration from private config if available
if yq '.github.docker_repo' "$PRIVATE_CONFIG" | grep -q "null"; then
  log_debug "No docker repository configuration found in private config"
  export DOCKER_REPO_ENABLED=false
else
  export DOCKER_REPO_ENABLED=true
  export DOCKER_REPO_URL=$(yq '.github.docker_repo.url' "$PRIVATE_CONFIG")
  export DOCKER_REPO_BRANCH=$(yq '.github.docker_repo.branch // "main"' "$PRIVATE_CONFIG")
  export DOCKER_REPO_DIRECTORY=$(yq '.github.docker_repo.directory' "$PRIVATE_CONFIG")
  export DOCKER_REPO_AUTO_UPDATE=$(yq '.github.docker_repo.auto_update // true' "$PRIVATE_CONFIG")
  log_debug "Docker repository configured: $DOCKER_REPO_URL ($DOCKER_REPO_BRANCH) → $DOCKER_REPO_DIRECTORY"
fi

# Network mounts configuration from private config if available
if yq '.network_mounts' "$PRIVATE_CONFIG" | grep -q "null"; then
  log_debug "No network mounts configuration found in private config"
  export NETWORK_MOUNTS_ENABLED=false
else
  export NETWORK_MOUNTS_ENABLED=true
  export NETWORK_MOUNTS_COUNT=$(yq '.network_mounts | length' "$PRIVATE_CONFIG")
  log_debug "Found $NETWORK_MOUNTS_COUNT network mounts configured"
fi

log_success "Configuration loaded successfully"