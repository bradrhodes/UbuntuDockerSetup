#!/usr/bin/env bash
# =================================================================
# Docker Repository Setup
# =================================================================
# Clones or updates the Docker configuration repository from GitHub
# =================================================================

# Source the logging module if not already loaded
if [ -z "$LOG_GREEN" ]; then
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
fi

# Setup Docker repository
setup_docker_repo() {
  log_section "Docker Repository Setup"

  # Check if Docker repo is enabled in config
  if [ "${DOCKER_REPO_ENABLED:-false}" != "true" ]; then
    log_info "Docker repository setup is not enabled in configuration"
    log_info "To enable, add github.docker_repo configuration to private.yml"
    return 0
  fi

  # Validate required configuration
  if [ -z "${DOCKER_REPO_URL:-}" ]; then
    log_error "Docker repository URL not specified in configuration"
    return 1
  fi

  if [ -z "${DOCKER_REPO_DIRECTORY:-}" ]; then
    log_error "Docker repository target directory not specified in configuration"
    return 1
  fi

  # Use default branch if not specified
  local branch=${DOCKER_REPO_BRANCH:-main}
  local auto_update=${DOCKER_REPO_AUTO_UPDATE:-true}
  
  log_info "Setting up Docker repository from: $DOCKER_REPO_URL"
  log_info "Target directory: $DOCKER_REPO_DIRECTORY"
  log_info "Branch: $branch"
  
  # Expand any ~ in the path to the home directory
  EXPANDED_REPO_DIR="${DOCKER_REPO_DIRECTORY/#\~/$HOME}"
  
  # Create parent directory if it doesn't exist
  if [ ! -d "$(dirname "$EXPANDED_REPO_DIR")" ]; then
    log_info "Creating parent directory: $(dirname "$EXPANDED_REPO_DIR")"
    
    # Create directory without sudo 
    if ! mkdir -p "$(dirname "$EXPANDED_REPO_DIR")"; then
      log_error "Failed to create parent directory $(dirname "$EXPANDED_REPO_DIR")"
      return 1
    fi
    
    log_success "Parent directory created successfully"
  fi
  
  # If the directory already exists, update it
  if [ -d "$EXPANDED_REPO_DIR/.git" ]; then
    log_info "Repository already exists at $DOCKER_REPO_DIRECTORY"
    
    if [ "$auto_update" = "true" ]; then
      log_info "Updating repository..."
      
      # Change to the repository directory
      cd "$EXPANDED_REPO_DIR" || { 
        log_error "Failed to change to repository directory"
        return 1
      }
      
      # Fetch the latest changes
      if ! git fetch origin; then
        log_error "Failed to fetch latest changes"
        return 1
      fi
      
      # Check current branch
      local current_branch
      current_branch=$(git rev-parse --abbrev-ref HEAD)
      
      # If we're on a different branch, checkout the desired branch
      if [ "$current_branch" != "$branch" ]; then
        log_info "Switching from branch $current_branch to $branch"
        if ! git checkout "$branch"; then
          log_error "Failed to switch to branch $branch"
          return 1
        fi
      fi
      
      # Pull the latest changes
      if ! git pull origin "$branch"; then
        log_error "Failed to pull latest changes"
        return 1
      fi
      
      log_success "Repository updated successfully"
    else
      log_info "Auto-update disabled, skipping update"
    fi
  else
    # Clone the repository if it doesn't exist
    log_info "Cloning repository to $DOCKER_REPO_DIRECTORY..."
    
    # If directory exists but is not a git repo, we need to handle this
    if [ -d "$EXPANDED_REPO_DIR" ]; then
      log_warn "Directory exists but is not a git repository"
      log_info "Checking if directory is empty..."
      
      if [ "$(ls -A "$EXPANDED_REPO_DIR")" ]; then
        log_error "Directory is not empty. Cannot clone repository."
        log_info "Please move or remove the contents of $DOCKER_REPO_DIRECTORY and try again."
        return 1
      else
        log_info "Directory is empty, proceeding with clone"
      fi
    else
      # Create the directory as current user (no sudo)
      log_info "Creating directory $DOCKER_REPO_DIRECTORY"
      if ! mkdir -p "$EXPANDED_REPO_DIR"; then
        log_error "Failed to create directory $DOCKER_REPO_DIRECTORY"
        return 1
      fi
    fi
    
    # We're always creating as the current user, so ownership is correct by default
    # Just make sure we have proper permissions
    if [ -d "$EXPANDED_REPO_DIR" ]; then
      log_info "Ensuring proper directory permissions"
      chmod -R u+w "$EXPANDED_REPO_DIR" 2>/dev/null || true
    fi
    
    # Clone the repository (as current user only)
    log_info "Running: git clone -b $branch $DOCKER_REPO_URL $EXPANDED_REPO_DIR"
    
    if ! git clone -b "$branch" "$DOCKER_REPO_URL" "$EXPANDED_REPO_DIR"; then
      log_error "Failed to clone repository"
      
      # If it failed, cleanup any partial directory
      if [ -d "$EXPANDED_REPO_DIR" ] && [ ! -d "$EXPANDED_REPO_DIR/.git" ]; then
        log_info "Cleaning up partial directory..."
        rm -rf "$EXPANDED_REPO_DIR"
      fi
      
      return 1
    fi
    
    log_success "Repository cloned successfully"
  fi
  
  # Display summary
  log_info "Docker configuration repository is ready at: $DOCKER_REPO_DIRECTORY"
  log_info "Branch: $branch"
  
  return 0
}

# Run the function directly if the script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_docker_repo
fi