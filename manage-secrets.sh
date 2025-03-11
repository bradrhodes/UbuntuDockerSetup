#!/usr/bin/env bash
# =================================================================
# Secret Configuration Manager
# =================================================================
# This script provides easy commands to manage your encrypted
# private configuration file with SOPS, similar to ansible-vault.
# The unencrypted file never persists on disk.
# Uses Age for encryption (simpler alternative to GPG).
# =================================================================

set -e  # Exit on error

# Source the logging module
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/scripts/logging.sh"

# Default file name - we only store the encrypted version
PRIVATE_CONFIG="$SCRIPT_DIR/config/private.yml"
PRIVATE_EXAMPLE="$SCRIPT_DIR/config/private.example.yml"
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# Check if a command exists
check_cmd() {
  if command -v "$1" &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# Helper function to mask Age keys for logging
mask_age_key() {
  local key="$1"
  # Keep the "age" prefix and first 5 chars, replace the rest with ***
  if [[ "$key" =~ ^age ]]; then
    echo "${key:0:8}***"
  else
    echo "***masked-key***"
  fi
}

# Function to edit the config file directly (primary method)
edit_config() {
  local file=${1:-$PRIVATE_CONFIG}
  
  if [ -f "$file" ]; then
    log_info "Opening encrypted file $file for editing..."
    sops "$file"
    log_success "Editing complete. Changes saved to $file"
  else
    log_info "File $file doesn't exist yet. Creating from example..."
    initialize "$file"
  fi
}

# Function to view the config without decrypting to a file
view_config() {
  local file=${1:-$PRIVATE_CONFIG}
  
  if [ ! -f "$file" ]; then
    log_fatal "File $file does not exist."
  fi
  
  log_info "Viewing encrypted file $file..."
  sops --decrypt "$file"
}

# Function to validate YAML syntax
validate_yaml() {
  local file=${1:-$PRIVATE_CONFIG}
  
  if [ ! -f "$file" ]; then
    log_fatal "File $file does not exist."
  fi
  
  if check_cmd yq; then
    log_info "Validating YAML syntax of $file..."
    if sops --decrypt "$file" | yq eval '.' - > /dev/null; then
      log_success "YAML syntax is valid."
    else
      log_error "YAML syntax is invalid. Please check your file."
    fi
  else
    log_warn "yq is not installed. Skipping YAML validation."
  fi
}

# Function to encrypt a file in-place
encrypt_file() {
  local file="$1"
  
  if [ ! -f "$file" ]; then
    log_fatal "File $file does not exist."
  fi
  
  log_info "Encrypting file: $file"
  
  # Make sure Age key environment variable is set
  if [ -z "$SOPS_AGE_KEY_FILE" ]; then
    export SOPS_AGE_KEY_FILE=$AGE_KEY_FILE
    log_info "Setting SOPS_AGE_KEY_FILE to $SOPS_AGE_KEY_FILE"
  fi
  
  # Check if the key file exists
  if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
    log_fatal "Age key file not found at $SOPS_AGE_KEY_FILE. Please run ./age-key-setup.sh first."
  fi
  
  # Extract public key for encryption
  PUBLIC_KEY=$(grep "public key:" "$SOPS_AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
  if [ -z "$PUBLIC_KEY" ]; then
    log_fatal "Failed to extract public key from $SOPS_AGE_KEY_FILE"
  fi
  
  # Create a temporary file for the encrypted content
  TEMP_FILE=$(mktemp)
  trap 'rm -f "$TEMP_FILE"' EXIT
  
  # Encrypt the file with explicit key
  log_info "Using Age public key: $PUBLIC_KEY"
  if sops --encrypt --age "$PUBLIC_KEY" "$file" > "$TEMP_FILE"; then
    # Replace the original file with the encrypted version
    mv "$TEMP_FILE" "$file"
    log_success "File encrypted successfully: $file"
  else
    log_error "Encryption failed"
    rm -f "$TEMP_FILE"
    return 1
  fi
}

# Function to initialize from example
initialize() {
  local example_file=${PRIVATE_EXAMPLE}
  local output_file=${1:-$PRIVATE_CONFIG}
  
  # Ensure config directory exists
  mkdir -p "$(dirname "$output_file")"
  
  if [ ! -f "$example_file" ]; then
    log_fatal "Example file $example_file does not exist."
  fi
  
  if [ -f "$output_file" ]; then
    read -p "File $output_file already exists. Overwrite? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Operation cancelled."
      exit 0
    fi
  fi
  
  # Create a temporary file for editing
  TEMP_FILE=$(mktemp)
  trap 'rm -f "$TEMP_FILE"' EXIT
  
  # Copy the example to the temp file
  cp "$example_file" "$TEMP_FILE"
  
  # Let the user edit the temp file with their preferred editor
  ${EDITOR:-vi} "$TEMP_FILE"
  
  log_info "Creating encrypted file from edited content..."
  if ! sops --input-type yaml --output-type yaml --encrypt "$TEMP_FILE" > "$output_file"; then
    log_error "Encryption failed. Please check your SOPS configuration."
    rm -f "$TEMP_FILE"
    return 1
  fi
  log_success "Encrypted file saved as $output_file"
}

# Function to add a new key and re-encrypt
rekey_config() {
  log_section "Adding New Key & Re-encrypting"
  
  if [ "$#" -ne 1 ]; then
    log_fatal "Please provide the new public key: $0 rekey <public_key>"
  fi
  
  NEW_PUBLIC_KEY="$1"
  
  # Validate that we're getting an Age public key (basic validation)
  if [[ ! "$NEW_PUBLIC_KEY" =~ ^age.* ]]; then
    log_fatal "The provided key doesn't appear to be an Age public key (should start with 'age')"
  fi
  
  # Check if SOPS config exists
  SOPS_CONFIG_FILE="$SCRIPT_DIR/config/.sops.yaml"
  if [ ! -f "$SOPS_CONFIG_FILE" ]; then
    log_fatal "SOPS config file not found at $SOPS_CONFIG_FILE"
  fi
  
  # Check if private.yml exists
  PRIVATE_FILE="$SCRIPT_DIR/config/private.yml"
  if [ ! -f "$PRIVATE_FILE" ]; then
    log_fatal "Encrypted file not found at $PRIVATE_FILE"
  fi
  
  # Make a backup of the encrypted file before we start
  cp "$PRIVATE_FILE" "$PRIVATE_FILE.bak"
  log_info "Created backup of encrypted file at $PRIVATE_FILE.bak"
  
  # First, decrypt the file to a temporary location
  log_info "Decrypting current file..."
  TEMP_DECRYPTED=$(mktemp)
  if ! sops --decrypt "$PRIVATE_FILE" > "$TEMP_DECRYPTED"; then
    log_error "Failed to decrypt $PRIVATE_FILE"
    rm -f "$TEMP_DECRYPTED"
    return 1
  fi
  log_success "Successfully decrypted the file"
  
  # Back up the original SOPS config
  SOPS_CONFIG_BACKUP="$SOPS_CONFIG_FILE.bak"
  cp "$SOPS_CONFIG_FILE" "$SOPS_CONFIG_BACKUP"
  log_info "Original SOPS config backed up to $SOPS_CONFIG_BACKUP"
  
  # Check if the key is already in the config
  if grep -q "$NEW_PUBLIC_KEY" "$SOPS_CONFIG_FILE"; then
    log_info "The provided key is already in the SOPS configuration"
    rm -f "$TEMP_DECRYPTED"
    rm -f "$PRIVATE_FILE.bak" "$SOPS_CONFIG_BACKUP"
    return 0
  fi
  
  # Extract existing keys and their format
  CONFIG_FORMAT="list"  # Default to list format
  EXISTING_KEYS=()
  
  # Determine format and extract keys
  if grep -q "age:" "$SOPS_CONFIG_FILE"; then
    # Check if it's a block scalar format
    if grep -q "age:.*>" "$SOPS_CONFIG_FILE"; then
      CONFIG_FORMAT="block"
      # Extract keys from block scalar format
      in_age_block=false
      while IFS= read -r line; do
        # Check if we're in the age block
        if [[ "$line" =~ age:[[:space:]]*\> ]]; then
          in_age_block=true
          continue
        fi
        
        # If we're in the age block and line starts with whitespace, it's likely a key
        if [ "$in_age_block" = true ] && [[ "$line" =~ ^[[:space:]]+(age.*) ]]; then
          key="${BASH_REMATCH[1]}"
          # Remove any trailing commas
          key="${key%,}"
          EXISTING_KEYS+=("$key")
        elif [ "$in_age_block" = true ] && [[ ! "$line" =~ ^[[:space:]] ]]; then
          # If we were in the age block and hit a line that doesn't start with whitespace, we're done
          in_age_block=false
        fi
      done < "$SOPS_CONFIG_FILE"
    else
      # Look for list format (with leading dash)
      while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(age.*) ]]; then
          key="${BASH_REMATCH[1]}"
          EXISTING_KEYS+=("$key")
        fi
      done < "$SOPS_CONFIG_FILE"
    fi
  fi
  
  # Create a safer .sops.yaml with a more lenient path regex
  {
    echo "creation_rules:"
    echo "  # Encrypt with Age key"
    # Using a more permissive regex that will match any path
    echo "  - path_regex: .*"
    
    if [ "$CONFIG_FORMAT" = "block" ]; then
      # Use block scalar format
      echo "    age: >-"
      
      # Add all existing keys with proper indentation
      for key in "${EXISTING_KEYS[@]}"; do
        echo "      $key,"
      done
      
      # Add the new key (no trailing comma for last item)
      echo "      $NEW_PUBLIC_KEY"
    else
      # Use list format
      echo "    age:"
      
      # Add all existing keys with proper indentation
      for key in "${EXISTING_KEYS[@]}"; do
        echo "      - $key"
      done
      
      # Add the new key
      echo "      - $NEW_PUBLIC_KEY"
    fi
  } > "$SOPS_CONFIG_FILE"
  
  # Validate the generated YAML
  if check_cmd yq && ! yq eval . "$SOPS_CONFIG_FILE" > /dev/null 2>&1; then
    log_error "Generated YAML is invalid. Restoring backup."
    cat "$SOPS_CONFIG_BACKUP" > "$SOPS_CONFIG_FILE"
    rm -f "$TEMP_DECRYPTED"
    rm -f "$PRIVATE_FILE.bak" "$SOPS_CONFIG_BACKUP"
    return 1
  fi
  
  log_success "Added new key to SOPS config"
  
  # Capture detailed error output for debugging
  ERROR_LOG=$(mktemp)
  
  # Use the config file to encrypt, with detailed error logging
  log_info "Using config file: $SOPS_CONFIG_FILE"
  log_info "Encrypting file: $TEMP_DECRYPTED ($(realpath "$TEMP_DECRYPTED"))"
  log_info "Attempting to encrypt with the following keys:"
  for key in "${EXISTING_KEYS[@]}"; do
    masked_key=$(mask_age_key "$key")
    log_info "  - $masked_key"
  done
  masked_new_key=$(mask_age_key "$NEW_PUBLIC_KEY")
  log_info "  - $masked_new_key"
  
  # Mask keys in the config file for logging
  log_info "Content of $SOPS_CONFIG_FILE (with masked keys):"
  cat "$SOPS_CONFIG_FILE" | sed -E 's/(age[a-zA-Z0-9]{5})[a-zA-Z0-9]+/\1***/g'
  
  # Try to encrypt directly with explicit keys first as a test
  ALL_KEYS=""
  for key in "${EXISTING_KEYS[@]}"; do
    if [ -z "$ALL_KEYS" ]; then
      ALL_KEYS="$key"
    else
      ALL_KEYS="$ALL_KEYS,$key"
    fi
  done
  if [ -z "$ALL_KEYS" ]; then
    ALL_KEYS="$NEW_PUBLIC_KEY"
  else
    ALL_KEYS="$ALL_KEYS,$NEW_PUBLIC_KEY"
  fi
  
  log_info "Testing if encryption works with explicit keys (masked for security)"
  masked_keys=$(echo "$ALL_KEYS" | sed -E 's/(age[a-zA-Z0-9]{5})[a-zA-Z0-9]+/\1***/g')
  log_info "Using: $masked_keys"
  if ! sops --input-type yaml --output-type yaml --encrypt --age "$ALL_KEYS" "$TEMP_DECRYPTED" > /dev/null 2> "$ERROR_LOG"; then
    log_error "Basic encryption test failed. Age keys may be invalid."
    log_error "--- Error details begin ---"
    cat "$ERROR_LOG"
    log_error "--- Error details end ---"
    log_error "Restoring original file and config."
    
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    cat "$SOPS_CONFIG_BACKUP" > "$SOPS_CONFIG_FILE"
    rm -f "$TEMP_DECRYPTED" "$ERROR_LOG" 2>/dev/null
    return 1
  fi
  log_success "Basic encryption test passed"
  
  # Now try with the config file, using specific format options
  if ! SOPS_AGE_RECIPIENTS="$ALL_KEYS" sops --config "$SOPS_CONFIG_FILE" --input-type yaml --output-type yaml --encrypt "$TEMP_DECRYPTED" > "$PRIVATE_FILE.new" 2> "$ERROR_LOG"; then
    log_error "Re-encryption failed using the config file method."
    log_error "--- Error details begin ---"
    cat "$ERROR_LOG"
    log_error "--- Error details end ---"
    log_error "Restoring original file and config."
    
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    cat "$SOPS_CONFIG_BACKUP" > "$SOPS_CONFIG_FILE"
    rm -f "$TEMP_DECRYPTED" "$PRIVATE_FILE.new" "$ERROR_LOG" 2>/dev/null
    return 1
  fi
  
  # Move the new file into place
  mv "$PRIVATE_FILE.new" "$PRIVATE_FILE"
  
  # After successful re-encryption, recreate the original regex pattern
  {
    echo "creation_rules:"
    echo "  # Encrypt with Age key"
    echo "  - path_regex: config/private.*\\.ya?ml$"
    
    if [ "$CONFIG_FORMAT" = "block" ]; then
      # Use block scalar format
      echo "    age: >-"
      
      # Add all existing keys with proper indentation
      for key in "${EXISTING_KEYS[@]}"; do
        echo "      $key,"
      done
      
      # Add the new key (no trailing comma for last item)
      echo "      $NEW_PUBLIC_KEY"
    else
      # Use list format
      echo "    age:"
      
      # Add all existing keys with proper indentation
      for key in "${EXISTING_KEYS[@]}"; do
        echo "      - $key"
      done
      
      # Add the new key
      echo "      - $NEW_PUBLIC_KEY"
    fi
  } > "$SOPS_CONFIG_FILE"
  
  # Verify that the file can be properly decrypted with the new configuration
  log_info "Verifying re-encryption..."
  TEMP_VERIFY=$(mktemp)
  if ! sops --decrypt "$PRIVATE_FILE" > "$TEMP_VERIFY"; then
    log_error "Verification failed, cannot decrypt the re-encrypted file. Restoring original file and config."
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    cat "$SOPS_CONFIG_BACKUP" > "$SOPS_CONFIG_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$PRIVATE_FILE.new" 2>/dev/null
    return 1
  fi
  
  # Verify content matches exactly
  if ! diff -q "$TEMP_DECRYPTED" "$TEMP_VERIFY" > /dev/null; then
    log_error "Verification failed, decrypted content doesn't match original. Restoring original file and config."
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    cat "$SOPS_CONFIG_BACKUP" > "$SOPS_CONFIG_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$PRIVATE_FILE.new" 2>/dev/null
    return 1
  fi
  
  log_success "Verification successful - decryption works with the new configuration"
  
  # Clean up all files
  rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$PRIVATE_FILE.bak" "$SOPS_CONFIG_BACKUP" "$PRIVATE_FILE.new" 2>/dev/null
  log_info "All temporary and backup files have been removed"
  
  log_success "The file has been rekeyed and can now be decrypted with the new key"
}

# Function to re-encrypt after manual key changes
reencrypt_config() {
  log_section "Re-encrypting Configuration"
  
  # Check if SOPS config exists
  SOPS_CONFIG_FILE="$SCRIPT_DIR/config/.sops.yaml"
  if [ ! -f "$SOPS_CONFIG_FILE" ]; then
    log_fatal "SOPS config file not found at $SOPS_CONFIG_FILE"
  fi
  
  # Check if private.yml exists
  PRIVATE_FILE="$SCRIPT_DIR/config/private.yml"
  if [ ! -f "$PRIVATE_FILE" ]; then
    log_fatal "Encrypted file not found at $PRIVATE_FILE"
  fi
  
  log_info "After removing keys from .sops.yaml, re-encryption is necessary"
  log_info "This ensures the file can't be decrypted with removed keys"
  
  # Make a backup of the encrypted file
  cp "$PRIVATE_FILE" "$PRIVATE_FILE.bak"
  log_info "Created backup of encrypted file"
  
  # Decrypt the private.yml file to a temporary file
  log_info "Decrypting current file..."
  TEMP_DECRYPTED=$(mktemp)
  if ! sops --decrypt "$PRIVATE_FILE" > "$TEMP_DECRYPTED"; then
    log_error "Failed to decrypt $PRIVATE_FILE"
    rm -f "$TEMP_DECRYPTED"
    return 1
  fi
  
  # Extract keys from the config file
  CONFIG_FORMAT="list"  # Default to list format
  EXISTING_KEYS=()
  
  # Determine format and extract keys
  if grep -q "age:" "$SOPS_CONFIG_FILE"; then
    # Check if it's a block scalar format
    if grep -q "age:.*>" "$SOPS_CONFIG_FILE"; then
      CONFIG_FORMAT="block"
      # Extract keys from block scalar format
      in_age_block=false
      while IFS= read -r line; do
        # Check if we're in the age block
        if [[ "$line" =~ age:[[:space:]]*\> ]]; then
          in_age_block=true
          continue
        fi
        
        # If we're in the age block and line starts with whitespace, it's likely a key
        if [ "$in_age_block" = true ] && [[ "$line" =~ ^[[:space:]]+(age.*) ]]; then
          key="${BASH_REMATCH[1]}"
          # Remove any trailing commas
          key="${key%,}"
          EXISTING_KEYS+=("$key")
        elif [ "$in_age_block" = true ] && [[ ! "$line" =~ ^[[:space:]] ]]; then
          # If we were in the age block and hit a line that doesn't start with whitespace, we're done
          in_age_block=false
        fi
      done < "$SOPS_CONFIG_FILE"
    else
      # Look for list format (with leading dash)
      while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(age.*) ]]; then
          key="${BASH_REMATCH[1]}"
          EXISTING_KEYS+=("$key")
        fi
      done < "$SOPS_CONFIG_FILE"
    fi
  fi
  
  # Print the keys found (masked)
  log_info "Found the following keys:"
  for key in "${EXISTING_KEYS[@]}"; do
    masked_key=$(mask_age_key "$key")
    log_info "  - $masked_key"
  done
  
  if [ ${#EXISTING_KEYS[@]} -eq 0 ]; then
    log_error "No keys found in the config file. Cannot continue."
    rm -f "$TEMP_DECRYPTED"
    return 1
  fi
  
  # Create a temporary config with a more permissive regex for the encryption
  TEMP_CONFIG=$(mktemp)
  {
    echo "creation_rules:"
    echo "  # Encrypt with Age key"
    # Using a more permissive regex that will match any path
    echo "  - path_regex: .*"
    
    if [ "$CONFIG_FORMAT" = "block" ]; then
      # Use block scalar format
      echo "    age: >-"
      
      # Add all existing keys with proper indentation (except last)
      for ((i=0; i<${#EXISTING_KEYS[@]}-1; i++)); do
        echo "      ${EXISTING_KEYS[i]},"
      done
      
      # Add the last key without trailing comma
      if [ ${#EXISTING_KEYS[@]} -gt 0 ]; then
        echo "      ${EXISTING_KEYS[${#EXISTING_KEYS[@]}-1]}"
      fi
    else
      # Use list format
      echo "    age:"
      
      # Add all existing keys with proper indentation
      for key in "${EXISTING_KEYS[@]}"; do
        echo "      - $key"
      done
    fi
  } > "$TEMP_CONFIG"
  
  # Generate a comma-separated list of keys for explicit encryption
  ALL_KEYS=""
  for ((i=0; i<${#EXISTING_KEYS[@]}; i++)); do
    if [ -z "$ALL_KEYS" ]; then
      ALL_KEYS="${EXISTING_KEYS[i]}"
    else
      ALL_KEYS="$ALL_KEYS,${EXISTING_KEYS[i]}"
    fi
  done
  
  # Re-encrypt with the updated key configuration
  log_info "Re-encrypting with current keys..."
  ERROR_LOG=$(mktemp)
  
  log_info "Using config: $TEMP_CONFIG"
  if ! SOPS_AGE_RECIPIENTS="$ALL_KEYS" sops --config "$TEMP_CONFIG" --input-type yaml --output-type yaml --encrypt "$TEMP_DECRYPTED" > "$PRIVATE_FILE.new" 2> "$ERROR_LOG"; then
    log_error "Re-encryption failed."
    log_error "--- Error details begin ---"
    cat "$ERROR_LOG"
    log_error "--- Error details end ---"
    log_error "Restoring original file."
    
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_CONFIG" "$PRIVATE_FILE.new" "$ERROR_LOG" 2>/dev/null
    return 1
  fi
  
  # Move the new file into place
  mv "$PRIVATE_FILE.new" "$PRIVATE_FILE"
  
  # Verify that the file can be properly decrypted
  log_info "Verifying re-encryption..."
  TEMP_VERIFY=$(mktemp)
  if ! sops --decrypt "$PRIVATE_FILE" > "$TEMP_VERIFY"; then
    log_error "Verification failed, cannot decrypt the re-encrypted file. Restoring original file."
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$TEMP_CONFIG" "$ERROR_LOG" 2>/dev/null
    return 1
  fi
  
  # Verify content matches
  if ! diff -q "$TEMP_DECRYPTED" "$TEMP_VERIFY" > /dev/null; then
    log_error "Verification failed, decrypted content doesn't match original. Restoring original file."
    mv "$PRIVATE_FILE.bak" "$PRIVATE_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$TEMP_CONFIG" "$ERROR_LOG" 2>/dev/null
    return 1
  fi
  
  log_success "Verification successful - decryption works with the new configuration"
  
  # Clean up all files
  rm -f "$TEMP_DECRYPTED" "$TEMP_VERIFY" "$TEMP_CONFIG" "$ERROR_LOG" "$PRIVATE_FILE.bak" 2>/dev/null
  log_info "Temporary files cleaned up"
  
  log_success "The file has been re-encrypted and can only be decrypted with current keys"
  log_info "Keys that were removed from .sops.yaml can no longer decrypt this file"
}


# Main logic based on command line arguments
case "$1" in
  edit)
    shift
    edit_config "$@"
    ;;
  view)
    shift
    view_config "$@"
    ;;
  validate)
    shift
    validate_yaml "$@"
    ;;
  init)
    shift
    initialize "$@"
    ;;
  encrypt)
    if [ -z "$2" ]; then
      log_fatal "Please specify a file to encrypt: $0 encrypt <filename>"
    fi
    encrypt_file "$2"
    ;;
  rekey)
    if [ -z "$2" ]; then
      log_fatal "Please specify a public key: $0 rekey <public_key>"
    fi
    rekey_config "$2"
    ;;
  reencrypt)
    reencrypt_config
    ;;
  *)
    echo "Usage: $0 <command> [file]"
    echo
    echo "Commands:"
    echo "  edit [file]     - Edit the encrypted file (creates if it doesn't exist)"
    echo "  view [file]     - View the decrypted contents without saving to disk"
    echo "  validate [file] - Validate YAML syntax"
    echo "  init [file]     - Initialize from example file"
    echo "  encrypt <file>  - Encrypt a file in-place (replaces plaintext with encrypted version)"
    echo "  rekey <key>     - Add a new public key and re-encrypt (for multi-machine setup)"
    echo "  reencrypt       - Re-encrypt file after maually editing .sops.yaml"
    echo
    echo "Default file: $PRIVATE_CONFIG"
    echo
    echo "Note: This tool never stores the unencrypted configuration on disk"
    echo "      (except temporarily during editing)"
    echo
    echo "To run the setup after managing secrets, use:"
    echo "  ./dev-env-setup.sh"
    ;;
esac