#!/usr/bin/env bash
# =================================================================
# Network Mounts Setup
# =================================================================
# This script sets up network mounts from the configuration
# and adds them to /etc/fstab for persistence.
# =================================================================

# Source the logging module if not already loaded
if [ -z "$LOG_GREEN" ]; then
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
fi

# Function to set up network mounts
setup_network_mounts() {
  log_section "Network Mounts Setup"
  
  # Check if network mounts are enabled in config
  if [ "${NETWORK_MOUNTS_ENABLED:-false}" != "true" ]; then
    log_info "Network mounts are not configured in private.yml"
    return 0
  fi
  
  log_info "Processing $NETWORK_MOUNTS_COUNT network mounts..."
  
  # Install required packages first
  log_subsection "Installing Required Packages"
  if ! command -v mount.nfs &> /dev/null; then
    log_info "Installing NFS client packages..."
    sudo apt-get update
    if ! sudo apt-get install -y nfs-common; then
      log_error "Failed to install NFS client packages"
      return 1
    fi
    log_success "NFS client packages installed"
  else
    log_success "NFS client packages already installed"
  fi
  
  # Create backup of fstab
  log_subsection "Backing up /etc/fstab"
  local backup_file="/etc/fstab.backup.$(date +%Y%m%d%H%M%S)"
  if ! sudo cp /etc/fstab "$backup_file"; then
    log_error "Failed to create backup of /etc/fstab"
    return 1
  fi
  log_success "Created backup of /etc/fstab at $backup_file"
  
  # Process each mount
  local mount_index=0
  local manual_mount_needed=false
  local mounts_added=0
  
  while [ $mount_index -lt $NETWORK_MOUNTS_COUNT ]; do
    local mount_type=$(yq ".network_mounts[$mount_index].type" "$PRIVATE_CONFIG")
    local mount_source=$(yq ".network_mounts[$mount_index].source" "$PRIVATE_CONFIG")
    local mount_target=$(yq ".network_mounts[$mount_index].target" "$PRIVATE_CONFIG")
    local mount_dump=$(yq ".network_mounts[$mount_index].dump // 0" "$PRIVATE_CONFIG")
    local mount_fsck=$(yq ".network_mounts[$mount_index].fsck // 0" "$PRIVATE_CONFIG")
    
    log_subsection "Configuring Mount: $mount_source → $mount_target"
    
    # Get permissions
    local mount_permissions_mode=$(yq ".network_mounts[$mount_index].permissions.mode // \"755\"" "$PRIVATE_CONFIG")
    local mount_permissions_owner=$(yq ".network_mounts[$mount_index].permissions.owner // \"$SERVER_USER\"" "$PRIVATE_CONFIG")
    local mount_permissions_group=$(yq ".network_mounts[$mount_index].permissions.group // \"$SERVER_USER\"" "$PRIVATE_CONFIG")
    
    # Process options
    local options_count=$(yq ".network_mounts[$mount_index].options | length" "$PRIVATE_CONFIG")
    local mount_options=""
    
    if [ "$options_count" -gt 0 ]; then
      for ((i=0; i<options_count; i++)); do
        local option=$(yq ".network_mounts[$mount_index].options[$i]" "$PRIVATE_CONFIG")
        if [ -z "$mount_options" ]; then
          mount_options="$option"
        else
          mount_options="$mount_options,$option"
        fi
      done
    else
      # Default options for NFS
      if [ "$mount_type" = "nfs" ]; then
        mount_options="defaults,noauto,nofail,x-systemd.automount,_netdev"
      else
        mount_options="defaults"
      fi
    fi
    
    # Check if systmed automount is enabled
    if [[ $mount_options == *"x-systemd.automount"* ]]; then
      log_info "This mount uses systemd automount, it will be mounted on first access"
    else
      manual_mount_needed=true
    fi
    
    # Create target directory if it doesn't exist
    if [ ! -d "$mount_target" ]; then
      log_info "Creating target directory: $mount_target"
      if ! sudo mkdir -p "$mount_target"; then
        log_error "Failed to create target directory: $mount_target"
        mount_index=$((mount_index + 1))
        continue
      fi
    fi
    
    # Set directory permissions
    log_info "Setting directory permissions: $mount_permissions_mode for $mount_permissions_owner:$mount_permissions_group"
    if ! sudo chmod "$mount_permissions_mode" "$mount_target"; then
      log_error "Failed to set directory permissions on $mount_target"
    fi
    
    # Set directory owner and group
    if ! sudo chown "$mount_permissions_owner:$mount_permissions_group" "$mount_target"; then
      log_error "Failed to set directory owner/group on $mount_target"
    fi
    
    # Check if mount entry already exists in fstab
    if grep -q "$mount_target" /etc/fstab; then
      log_info "Mount entry for $mount_target already exists in /etc/fstab"
    else
      # Create fstab entry
      local fstab_entry="$mount_source $mount_target $mount_type $mount_options $mount_dump $mount_fsck"
      log_info "Adding to /etc/fstab: $fstab_entry"
      
      # Add entry to fstab
      if ! echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null; then
        log_error "Failed to add mount entry to /etc/fstab"
      else
        log_success "Added mount entry to /etc/fstab"
        mounts_added=$((mounts_added + 1))
      fi
    fi
    
    mount_index=$((mount_index + 1))
  done
  
  # Reload systemd if any mounts were added
  if [ $mounts_added -gt 0 ]; then
    log_subsection "Reloading Systemd"
    sudo systemctl daemon-reload
    
    # Display instructions for manual mounting if needed
    if [ "$manual_mount_needed" = true ]; then
      log_info "Some mounts are configured without automount and need to be mounted manually."
      log_info "You can mount them using one of these methods:"
      log_info "1. Reboot the server: sudo reboot"
      log_info "2. Mount all entries from fstab: sudo mount -a"
      log_info "3. Mount individual entries: sudo mount <mount_point>"
    else
      log_info "All mounts use systemd automount and will be mounted on first access."
      log_info "To verify mounts, try accessing one of the mount points and then check with: df -h"
    fi
  fi
  
  log_success "Network mounts setup completed"
  return 0
}

# Run the function directly if the script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_network_mounts
fi