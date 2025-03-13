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
SOPS_CONFIG_FILE="$SCRIPT_DIR/config/.sops.yaml"

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
      return 0
    fi
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
  
  # Make sure config directory exists
  mkdir -p "$(dirname "$SOPS_CONFIG_FILE")"
  
  if [ -z "$PUBLIC_KEY" ]; then
    extract_public_key
  fi
  
  # Check if yq is installed
  if ! command -v yq &> /dev/null; then
    log_fatal "yq is required but not installed. Please run the bootstrap.sh script first to install required tools."
  fi
  
  # Check if this key is already added to avoid duplicates
  if [ -f "$SOPS_CONFIG_FILE" ] && grep -q "$PUBLIC_KEY" "$SOPS_CONFIG_FILE"; then
    log_info "Public key already exists in SOPS config"
    return 0
  fi
  
  if [ -f "$SOPS_CONFIG_FILE" ]; then
    log_info "Updating existing SOPS config..."
    # Create backup of existing config
    cp "$SOPS_CONFIG_FILE" "$SOPS_CONFIG_FILE.bak"
    log_info "Backup created at $SOPS_CONFIG_FILE.bak"
    
    # Check if there's an existing age key
    if yq '.creation_rules[0].age' "$SOPS_CONFIG_FILE" | grep -q -v "null"; then
      # Handle different age format types
      if yq '.creation_rules[0].age | type' "$SOPS_CONFIG_FILE" | grep -q "string"; then
        # Handle the block scalar (>-) format
        # We need to create a temporary file and process it
        TEMP_FILE=$(mktemp)
        
        # Extract all the age recipients from the file without our new key
        recipients=$(yq '.creation_rules[0].age' "$SOPS_CONFIG_FILE" | grep -v "$PUBLIC_KEY")
        
        # Create a new config with all existing recipients plus our new key
        yq eval '.creation_rules[0].age = env(recipients) + "\n      " + env(PUBLIC_KEY)' \
          --env="recipients=$recipients" --env="PUBLIC_KEY=$PUBLIC_KEY" \
          "$SOPS_CONFIG_FILE" > "$TEMP_FILE"
          
        # Replace the original file
        mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
      else
        # It's likely an array - add our key to it
        TEMP_FILE=$(mktemp)
        # Add the new key to the array
        yq eval '.creation_rules[0].age += [env(PUBLIC_KEY)]' \
          --env="PUBLIC_KEY=$PUBLIC_KEY" \
          "$SOPS_CONFIG_FILE" > "$TEMP_FILE"
        # Replace the original file
        mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
      fi
    else
      # No age field yet, add it
      TEMP_FILE=$(mktemp)
      yq eval '.creation_rules[0].age = env(PUBLIC_KEY)' \
        --env="PUBLIC_KEY=$PUBLIC_KEY" \
        "$SOPS_CONFIG_FILE" > "$TEMP_FILE"
      # Replace the original file
      mv "$TEMP_FILE" "$SOPS_CONFIG_FILE"
    fi
  else
    log_info "Creating new SOPS config..."
    
    # Create new config with just the new key
    cat > "$SOPS_CONFIG_FILE" << EOF
creation_rules:
  - path_regex: config/private.*\.ya?ml$
    age: >-
      $PUBLIC_KEY
EOF
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