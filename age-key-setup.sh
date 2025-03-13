#!/usr/bin/env bash
# =================================================================
# Age Key Setup for SOPS
# =================================================================
# This script helps generate and configure Age keys for use with SOPS.
# Age is a simpler alternative to GPG for file encryption.
# =================================================================

set -e  # Exit on error

# Source the logging module
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/scripts/logging.sh"

# Use SOPS' standard key location
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# Always use a consistent, relative path for better portability
SOPS_CONFIG_FILE="$SCRIPT_DIR/config/.sops.yaml"

# Debug current config - remove this later
log_debug "Script directory: $SCRIPT_DIR"
log_debug "Age key file: $AGE_KEY_FILE"
log_debug "SOPS config file: $SOPS_CONFIG_FILE"

# Check if age is installed
check_age() {
  if ! command -v age &> /dev/null; then
    log_fatal "Age is not installed. Please run the bootstrap script first."
  fi
  
  if ! command -v age-keygen &> /dev/null; then
    log_fatal "Age-keygen is not installed. Please run the bootstrap script first."
  fi
  
  log_success "Age is installed"
}

# Generate a new Age key
generate_key() {
  log_section "Generating Age Key"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  
  # Check if key already exists
  if [ -f "$AGE_KEY_FILE" ]; then
    log_warn "Age key already exists at $AGE_KEY_FILE"
    read -p "Do you want to generate a new key? This will overwrite the existing key. (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Using existing key"
      extract_public_key
      update_sops_config  # Make sure the key is in .sops.yml
      return 0
    fi
    # If user confirmed, we'll continue and generate a new key below
  fi
  
  # Generate new key
  log_info "Generating new Age key..."
  age-keygen -o "$AGE_KEY_FILE"
  chmod 600 "$AGE_KEY_FILE"
  log_success "Age key generated at $AGE_KEY_FILE"
  
  extract_public_key
}

# Extract public key from the key file
extract_public_key() {
  if [ ! -f "$AGE_KEY_FILE" ]; then
    log_fatal "Age key file not found at $AGE_KEY_FILE"
  fi
  
  # Extract public key
  PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
  
  if [ -z "$PUBLIC_KEY" ]; then
    log_fatal "Failed to extract public key from $AGE_KEY_FILE"
  fi
  
  log_success "Public key extracted: $PUBLIC_KEY"
}

# Update SOPS config with the Age public key
update_sops_config() {
  log_section "Updating SOPS Configuration"
  
  # Debug info
  log_info "Current public key: $PUBLIC_KEY"
  
  # Make sure config directory exists
  mkdir -p "$(dirname "$SOPS_CONFIG_FILE")"
  log_info "SOPS config file path: $SOPS_CONFIG_FILE"
  
  if [ -z "$PUBLIC_KEY" ]; then
    log_info "No public key loaded, extracting from key file"
    extract_public_key
  fi
  
  # Safety check for public key
  if [ -z "$PUBLIC_KEY" ]; then
    log_fatal "Failed to extract public key, cannot update SOPS config"
  fi
  
  # Check if yq is installed
  if ! command -v yq &> /dev/null; then
    log_fatal "yq is required but not installed. Please run the bootstrap.sh script first to install required tools."
  fi
  
  # Check if SOPS config file exists
  if [ ! -f "$SOPS_CONFIG_FILE" ]; then
    log_info "SOPS config file does not exist, will create it"
  else 
    log_info "SOPS config file exists, checking for key"
  fi
  
  # Check if this key is already added to avoid duplicates
  if [ -f "$SOPS_CONFIG_FILE" ]; then
    log_info "Checking if key exists in config file..."
    if grep -q "$PUBLIC_KEY" "$SOPS_CONFIG_FILE"; then
      log_info "Public key already exists in SOPS config"
      return 0
    else
      log_info "Public key NOT found in config, will add it"
    fi
    
    # Debug - show current config content
    log_debug "Current config file content:"
    cat "$SOPS_CONFIG_FILE" | while read line; do
      log_debug "  $line"
    done
    
    log_info "Updating existing SOPS config..."
    # Create backup of existing config
    cp "$SOPS_CONFIG_FILE" "$SOPS_CONFIG_FILE.bak"
    log_info "Backup created at $SOPS_CONFIG_FILE.bak"
    
    # Check if there's an existing age key
    if yq '.creation_rules[0].age' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -q -v "null"; then
      # First, check if the key is already in the file regardless of format
      if grep -q "$PUBLIC_KEY" "$SOPS_CONFIG_FILE"; then
        log_info "Public key already exists in SOPS config"
        return 0
      fi
  
      # Handle different age format types
      if yq '.creation_rules[0].age | type' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -q "string"; then
        log_info "Detected block scalar format in config"
        
        # Extract existing keys from the block scalar format
        TEMP_FILE=$(mktemp)
        TEMP_KEYS=$(mktemp)
        
        # Extract existing keys and format
        yq '.creation_rules[0].age' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -v "null" > "$TEMP_KEYS" || true
        
        # Add our key to the list (appending to maintain existing keys)
        echo "$PUBLIC_KEY" >> "$TEMP_KEYS"
        
        # Get path_regex from existing file or use default
        path_regex=$(yq '.creation_rules[0].path_regex' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -v "null" || echo "config/private.*\.ya?ml$")
        
        # Create the new config file preserving the block scalar format
        {
          echo "creation_rules:"
          echo "  - path_regex: $path_regex"
          echo "    age: >-"
          
          # Add all keys maintaining the indentation
          while IFS= read -r key; do
            # Skip empty lines
            if [ -n "$key" ]; then
              echo "      $key"
            fi
          done < "$TEMP_KEYS"
        } > "$TEMP_FILE"
        
        # Debug - show what we're writing
        log_info "Writing new config with block scalar format:"
        cat "$TEMP_FILE" | while read debug_line; do
          log_info "  $debug_line"
        done
        
        # Clean up temp files
        rm -f "$TEMP_KEYS"
          
        # Replace the original file
        mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
      else
        # It's likely an array format - process accordingly
        if grep -q "$PUBLIC_KEY" "$SOPS_CONFIG_FILE"; then
          log_info "Public key already exists in SOPS config (array format)"
          return 0
        fi
        
        log_info "Adding key to existing config (array format)"
        
        TEMP_FILE=$(mktemp)
        TEMP_KEYS=$(mktemp)
        
        # Extract existing keys from the age array
        yq '.creation_rules[0].age[]' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -v "null" > "$TEMP_KEYS" || true
        
        # Add our key to the list
        echo "$PUBLIC_KEY" >> "$TEMP_KEYS"
        
        # Sort and remove duplicates
        sort -u "$TEMP_KEYS" > "$TEMP_KEYS.sorted"
        
        # Get path_regex from existing file or use default
        path_regex=$(yq '.creation_rules[0].path_regex' "$SOPS_CONFIG_FILE" 2>/dev/null | grep -v "null" || echo "config/private.*\.ya?ml$")
        
        # Create the new config file with all keys
        {
          echo "creation_rules:"
          echo "  - path_regex: $path_regex"
          echo "    age:"
          
          # Add all keys as array elements
          while IFS= read -r key; do
            # Skip empty lines
            if [ -n "$key" ]; then
              echo "      - \"$key\""
            fi
          done < "$TEMP_KEYS.sorted"
        } > "$TEMP_FILE"
        
        # Debug - show what we're writing
        log_info "Writing new config with the following content:"
        cat "$TEMP_FILE" | while read debug_line; do
          log_info "  $debug_line"
        done
        
        # Clean up temp files
        rm -f "$TEMP_KEYS" "$TEMP_KEYS.sorted"
        
        # Replace the original file
        mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
      fi
    else
      log_info "No age field found, creating it"
      
      # No age field yet, create a new SOPS config file
      TEMP_FILE=$(mktemp)
      
      # Simple approach to create a new config from scratch
      cat > "$TEMP_FILE" << EOF
creation_rules:
  - path_regex: config/private.*\.ya?ml$
    age: >-
      $PUBLIC_KEY
EOF
      
      # Replace the original file
      mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
      
      log_success "Created new SOPS config with age key"
    fi
  else
    log_info "Creating new SOPS config..."
    
    # Make sure the directory exists
    mkdir -p "$(dirname "$SOPS_CONFIG_FILE")"
    
    # Create new config with just the new key - using the original block scalar format
    cat > "$SOPS_CONFIG_FILE" << EOF
creation_rules:
  - path_regex: config/private.*\.ya?ml$
    age: >-
      $PUBLIC_KEY
EOF
    
    # Verify the file was created
    if [ -f "$SOPS_CONFIG_FILE" ]; then
      log_success "SOPS config file created successfully"
    else
      log_error "Failed to create SOPS config file"
    fi
  fi
  
  log_success "SOPS config updated with Age public key"
  log_info "Configuration file: $SOPS_CONFIG_FILE"
}

# Export key for use on another machine
export_key() {
  log_section "Exporting Age Key"
  
  if [ ! -f "$AGE_KEY_FILE" ]; then
    log_fatal "Age key file not found at $AGE_KEY_FILE"
  fi
  
  EXPORT_FILE="age-key-export.txt"
  
  # Copy key to export file
  cp "$AGE_KEY_FILE" "$EXPORT_FILE"
  chmod 600 "$EXPORT_FILE"
  
  log_success "Age key exported to $EXPORT_FILE"
  log_warn "IMPORTANT: This file contains your private key!"
  log_warn "Transfer it securely to your other machine"
  log_warn "After importing, the file will be automatically deleted"
}

# Import key from another machine
import_key() {
  log_section "Importing Age Key"
  
  if [ "$#" -ne 1 ]; then
    log_fatal "Please provide the path to the exported key file"
  fi
  
  IMPORT_FILE="$1"
  
  if [ ! -f "$IMPORT_FILE" ]; then
    log_fatal "Import file not found: $IMPORT_FILE"
  fi
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  
  # Check if key already exists
  if [ -f "$AGE_KEY_FILE" ]; then
    log_warn "Age key already exists at $AGE_KEY_FILE"
    read -p "Do you want to overwrite it? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Import cancelled"
      return 0
    fi
  fi
  
  # Copy key to Age directory
  cp "$IMPORT_FILE" "$AGE_KEY_FILE"
  chmod 600 "$AGE_KEY_FILE"
  
  log_success "Age key imported to $AGE_KEY_FILE"
  
  # Securely delete the imported file
  log_info "Securely removing imported key file..."
  
  # Try to use shred for secure deletion if available
  if command -v shred &> /dev/null; then
    shred -u "$IMPORT_FILE"
  else
    # Fallback to basic removal
    rm -f "$IMPORT_FILE"
  fi
  
  log_success "Imported key file removed for security"
  
  # Extract and configure
  extract_public_key
  update_sops_config
}

# Check for SOPS environment variable
setup_env_var() {
  log_section "Setting Up Environment Variables"
  
  if [ ! -f "$AGE_KEY_FILE" ]; then
    log_fatal "Age key file not found at $AGE_KEY_FILE"
  fi
  
  # Check if SOPS_AGE_KEY_FILE is already in shell config
  SHELL_CONFIG=""
  if [ -f "$HOME/.bashrc" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
  elif [ -f "$HOME/.zshrc" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
  elif [ -f "$HOME/.config/fish/config.fish" ]; then
    SHELL_CONFIG="$HOME/.config/fish/config.fish"
  fi
  
  if [ -n "$SHELL_CONFIG" ]; then
    if grep -q "SOPS_AGE_KEY_FILE" "$SHELL_CONFIG"; then
      log_info "SOPS_AGE_KEY_FILE already configured in $SHELL_CONFIG"
    else
      log_info "Adding SOPS_AGE_KEY_FILE to $SHELL_CONFIG"
      
      if [[ "$SHELL_CONFIG" == *"fish"* ]]; then
        echo "set -x SOPS_AGE_KEY_FILE $AGE_KEY_FILE" >> "$SHELL_CONFIG"
      else
        echo "export SOPS_AGE_KEY_FILE=$AGE_KEY_FILE" >> "$SHELL_CONFIG"
      fi
      
      log_success "Environment variable added to $SHELL_CONFIG"
      log_info "Please restart your shell or run: source $SHELL_CONFIG"
    fi
  else
    log_warn "Could not detect shell configuration file"
    log_info "Please add the following to your shell configuration:"
    log_info "export SOPS_AGE_KEY_FILE=$AGE_KEY_FILE"
  fi
  
  # Set for current session
  export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"
  log_success "SOPS_AGE_KEY_FILE set for current session"
}

# Initialize everything (generate + config + env)
init_all() {
  generate_key
  update_sops_config
  setup_env_var
  
  log_section "Next Steps"
  log_info "You're all set up to use Age with SOPS!"
  log_info "You can now run: ./manage-secrets.sh init"
}

# Print help
show_help() {
  echo "Age Key Setup for SOPS"
  echo
  echo "Usage: ./age-key-setup.sh [command]"
  echo
  echo "Commands:"
  echo "  init         Initialize everything (generate + config + env)"
  echo "  generate     Generate a new Age key pair"
  echo "  config       Update SOPS config with existing key"
  echo "  export       Export key for use on another machine"
  echo "  import FILE  Import key from FILE"
  echo "  env          Setup environment variables"
  echo "  help         Show this help message"
  echo
  echo "Without a command, shows this help message"
}

# Main function
main() {
  check_age
  
  if [ $# -eq 0 ]; then
    # Default: show help
    show_help
  else
    case "$1" in
      init)
        init_all
        ;;
      generate)
        generate_key
        ;;
      config)
        extract_public_key
        update_sops_config
        ;;
      export)
        extract_public_key
        export_key
        ;;
      import)
        import_key "$2"
        ;;
      env)
        setup_env_var
        ;;
      help|--help|-h)
        show_help
        ;;
      *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
    esac
  fi
}

# Run main function
main "$@"