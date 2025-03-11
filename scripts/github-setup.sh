#!/usr/bin/env bash
# =================================================================
# GitHub Configuration Setup
# =================================================================
# Uploads SSH keys to GitHub for repository access
# =================================================================

# Source the logging module if not already loaded
if [ -z "$LOG_GREEN" ]; then
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
fi

# Function to set up GitHub SSH access
setup_github() {
  log_section "Setting up GitHub SSH access"
  
  # Use SERVER_USER if available, otherwise use current user
  local user=${SERVER_USER:-$(whoami)}
  local home_dir=${SERVER_HOME_DIR:-$HOME}
  local ssh_dir="$home_dir/.ssh"
  local ssh_key="$ssh_dir/id_${SSH_KEY_TYPE:-ed25519}"
  
  if [ ! -f "$ssh_key.pub" ]; then
    log_warn "SSH public key not found at $ssh_key.pub, skipping GitHub setup"
    return 0
  fi
  
  if [ "${GITHUB_UPLOAD_KEY:-false}" != "true" ]; then
    log_info "GitHub SSH key upload disabled"
    log_info "To enable, set github.upload_key to true in private.yml"
    return 0
  fi
  
  if [ -z "${GITHUB_ACCESS_TOKEN:-}" ] || [ -z "${GITHUB_USERNAME:-}" ]; then
    log_warn "GitHub access token and/or username not provided, skipping GitHub SSH key upload"
    log_info "To manually add your SSH key to GitHub:"
    log_info "1. Copy the key: cat $ssh_key.pub"
    log_info "2. Go to https://github.com/settings/keys"
    log_info "3. Click 'New SSH key' and paste your key"
    return 0
  fi
  
  log_info "Checking if key is already on GitHub..."
  
  # Get the public key content
  local public_key=$(cat "$ssh_key.pub")
  local public_key_content=$(echo "$public_key" | cut -d ' ' -f 1-2)
  
  # Check if key already exists
  local key_exists=$(curl -s -H "Authorization: token $GITHUB_ACCESS_TOKEN" \
    "https://api.github.com/user/keys" | grep -F "$public_key_content")
  
  if [ -n "$key_exists" ]; then
    log_info "SSH key already exists on GitHub, skipping upload"
  else
    log_info "Uploading SSH key to GitHub..."
    
    # Create a unique key title
    local key_title="$(hostname)-$(date +%Y-%m-%d)"
    
    # Create a JSON payload for the GitHub API
    local json_payload=$(mktemp)
    cat > "$json_payload" << EOF
{
  "title": "$key_title",
  "key": "$public_key"
}
EOF
    
    # Upload the key using the GitHub API
    local response=$(curl -s -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: token $GITHUB_ACCESS_TOKEN" \
      -d @"$json_payload" \
      "https://api.github.com/user/keys")
    
    # Remove the temporary file
    rm "$json_payload"
    
    # Check if the request was successful
    if echo "$response" | grep -q "\"id\""; then
      log_success "SSH key uploaded to GitHub successfully"
    else
      log_error "Failed to upload SSH key to GitHub: $response"
    fi
  fi
  
  # Test the SSH connection to GitHub
  log_info "Testing GitHub SSH connection..."
  if ssh -T -o StrictHostKeyChecking=no git@github.com 2>&1 | grep -q "success"; then
    log_success "GitHub SSH connection successful"
  else
    log_warn "GitHub SSH connection test returned unexpected response"
    log_info "This might be normal if this is the first connection from this machine"
  fi
  
  return 0
}

# Run the function directly if the script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_github
fi