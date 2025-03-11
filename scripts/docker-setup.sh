#!/usr/bin/env bash
# =================================================================
# Docker Setup Script
# =================================================================
# This script installs Docker and Docker Compose and configures them
# to start on boot.
# =================================================================

# Source the logging module if not already loaded
if [ -z "$LOG_GREEN" ]; then
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  source "$SCRIPT_DIR/logging.sh"
fi

# Install Docker and Docker Compose
setup_docker() {
  log_section "Docker Installation"
  
  # Check if Docker is already installed
  if command -v docker &> /dev/null; then
    log_info "Docker is already installed, version: $(docker --version)"
  else
    log_info "Installing Docker..."
    
    # Add Docker's official GPG key
    log_subsection "Setting up Docker Repository"
    log_info "Adding Docker's official GPG key..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the Docker repository
    log_info "Setting up the Docker repository..."
    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      \"$(. /etc/os-release && echo "$VERSION_CODENAME")\" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    log_subsection "Installing Docker Engine"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verify Docker is installed
    if command -v docker &> /dev/null; then
      log_success "Docker installed successfully, version: $(docker --version)"
    else
      log_error "Docker installation failed"
      return 1
    fi
  fi
  
  # Docker Compose is now included via the docker-compose-plugin
  if docker compose version &> /dev/null; then
    log_info "Docker Compose plugin is already installed, version: $(docker compose version)"
  else
    log_warn "Docker Compose plugin not found despite installation. This may indicate an issue."
  fi
  
  # Add current user to docker group to avoid needing sudo for docker commands
  if getent group docker &> /dev/null; then
    if groups "$USER" | grep -q '\bdocker\b'; then
      log_info "User $USER is already in the docker group"
    else
      log_info "Adding user $USER to the docker group..."
      sudo usermod -aG docker "$USER"
      log_success "User added to docker group. You'll need to log out and back in for this to take effect."
    fi
  else
    log_error "Docker group does not exist. This may indicate an issue with the Docker installation."
  fi
  
  # Start Docker daemon and enable on boot
  log_subsection "Starting Docker Service"
  log_info "Starting Docker service and enabling on boot..."
  sudo systemctl start docker
  sudo systemctl enable docker
  
  # Check if Docker service is running
  if sudo systemctl is-active --quiet docker; then
    log_success "Docker service is running"
  else
    log_error "Docker service is not running. Please check the Docker installation."
    return 1
  fi
  
  # Quick verification with a simple container
  log_subsection "Verifying Docker Installation"
  log_info "Running a test container..."
  if sudo docker run --rm hello-world | grep -q "Hello from Docker!"; then
    log_success "Docker test container ran successfully"
  else
    log_error "Docker test container failed to run. Please check the Docker installation."
    return 1
  fi
  
  return 0
}

# Run the function directly if the script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_docker
fi