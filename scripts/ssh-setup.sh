#!/usr/bin/env bash
# =================================================================
# SSH Configuration Setup
# =================================================================
# Sets up SSH keys based on configuration in private.yml
# =================================================================

# Source the logging module if not already loaded
if [ -z "$LOG_GREEN" ]; then
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
fi

# Function to set up SSH
setup_ssh() {
  log_section "Setting up SSH"
  
  # Use SERVER_USER if available, otherwise use current user
  local user=${SERVER_USER:-$(whoami)}
  local home_dir=${SERVER_HOME_DIR:-$HOME}
  local ssh_dir="$home_dir/.ssh"
  local ssh_key="$ssh_dir/id_${SSH_KEY_TYPE:-ed25519}"

  log_info "Using SSH directory: $ssh_dir"
  log_info "SSH key path: $ssh_key"

  # Create SSH directory if it doesn't exist
  if [ ! -d "$ssh_dir" ]; then
    log_info "Creating SSH directory..."
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    log_success "SSH directory created"
  else
    log_info "SSH directory already exists"
  fi

  # Check if SSH_GENERATE_KEY is defined and true
  if [ "${SSH_GENERATE_KEY:-false}" = "true" ]; then
    if [ ! -f "$ssh_key" ]; then
      log_info "Generating new SSH key..."
      
      # Check if we need to use a passphrase
      if [ -n "${SSH_KEY_PASSPHRASE:-}" ]; then
        # Create a temporary file for the passphrase
        local passphrase_file=$(mktemp)
        echo "$SSH_KEY_PASSPHRASE" > "$passphrase_file"
        
        # Generate the key with passphrase
        ssh-keygen -t "${SSH_KEY_TYPE:-ed25519}" -C "${SSH_KEY_EMAIL:-}" -f "$ssh_key" -N "$(cat $passphrase_file)"
        
        # Remove the temporary file
        rm "$passphrase_file"
      else
        # Generate without passphrase
        ssh-keygen -t "${SSH_KEY_TYPE:-ed25519}" -C "${SSH_KEY_EMAIL:-}" -f "$ssh_key" -N ""
      fi
      
      # Set proper ownership if running as root for another user
      if [ "$(id -u)" -eq 0 ] && [ "$user" != "root" ]; then
        chown "$user:$user" "$ssh_key" "$ssh_key.pub"
      fi
      
      log_success "SSH key generated at: $ssh_key"
      log_info "Public key: $(cat "$ssh_key.pub")"
    else
      log_info "SSH key already exists at $ssh_key, skipping generation"
    fi
    
    # Start the SSH agent if we're in an interactive shell
    if [ -t 0 ]; then
      log_info "Starting SSH agent..."
      eval "$(ssh-agent -s)"
    
      # Add the key to the agent
      if [ -n "${SSH_KEY_PASSPHRASE:-}" ]; then
        # Create a temporary file for the passphrase
        local passphrase_file=$(mktemp)
        echo "$SSH_KEY_PASSPHRASE" > "$passphrase_file"
        
        # Add with passphrase
        SSH_ASKPASS="$passphrase_file" ssh-add "$ssh_key" < /dev/null
        
        # Remove the temporary file
        rm "$passphrase_file"
      else
        # Add without passphrase
        ssh-add "$ssh_key"
      fi
      
      log_success "SSH key added to agent"
    else
      log_info "Not an interactive shell, skipping ssh-agent setup"
    fi
  else
    log_info "SSH key generation disabled in configuration"
    log_info "To enable, set ssh.generate_key to true in private.yml"
  fi

  return 0
}

# Run the function directly if the script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_ssh
fi