# Ubuntu Server Setup for Docker

A secure, automated solution for setting up Ubuntu servers to run Docker containers with encrypted configuration management.

## Table of Contents
- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
  - [First-time Setup (Creating New Configuration)](#first-time-setup-creating-new-configuration)
  - [Additional Server Setup (Using Existing Configuration)](#additional-server-setup-using-existing-configuration)
- [Setup Process](#setup-process)
  - [1. Bootstrap](#1-bootstrap)
  - [2. Secret Management](#2-secret-management)
    - [Initial Configuration](#initial-configuration)
    - [Working with Encrypted Configuration](#working-with-encrypted-configuration)
  - [3. SSH and GitHub Setup](#3-ssh-and-github-setup)
  - [4. Docker Repository Setup](#4-docker-repository-setup)
  - [5. Network Mounts](#5-network-mounts)
- [Using Existing Encrypted Configuration](#using-existing-encrypted-configuration)
- [Configuration Options](#configuration-options)
  - [Public Configuration (public.yml)](#public-configuration-publicyml)
  - [Private Configuration (private.yml)](#private-configuration-privateyml)
- [Scripts](#scripts)
  - [bootstrap.sh](#bootstrapsh)
  - [manage-secrets.sh](#manage-secretssh)
  - [server-setup.sh](#server-setupsh)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

## Overview

This toolkit provides scripts to set up Ubuntu servers for running Docker containers. It includes:

- Bootstrap process to install essential prerequisites
- Secure management of sensitive configuration using SOPS with Age encryption
- Docker and Docker Compose installation and configuration
- SSH key generation and GitHub integration
- Network mounts setup and configuration
- Docker repository cloning and management

## Directory Structure
```
/
├── bootstrap.sh         # Installs prerequisites 
├── age-key-setup.sh     # Sets up Age encryption keys
├── manage-secrets.sh    # Manages encrypted configuration
├── server-setup.sh      # Main setup script (handles decryption)
├── README.md
├── config/
│   ├── public.yml       # Public configuration
│   ├── private.yml      # Encrypted private configuration
│   ├── private.example.yml  # Template for private configuration
│   └── .sops.yaml       # SOPS encryption configuration
└── scripts/
    ├── logging.sh       # Centralized logging module
    ├── load-config.sh   # Configuration loading script
    ├── docker-setup.sh  # Docker installation script
    ├── ssh-setup.sh     # SSH key generation script
    ├── github-setup.sh  # GitHub integration script
    ├── docker-repo-setup.sh # Docker repo cloning script
    └── network-mounts-setup.sh # Network mounts script
```

## Quick Start

### First-time Setup (Creating New Configuration)

```bash
# 1. Clone this repository
git clone https://github.com/yourusername/UbuntuServerSetup.git
cd UbuntuServerSetup

# 2. Make all scripts executable
chmod +x *.sh scripts/*.sh

# 3. Run the bootstrap script to install prerequisites (including Age)
./bootstrap.sh

# 4. Set up your Age key and SOPS configuration
./age-key-setup.sh init

# 5. Initialize your private configuration
./manage-secrets.sh init

# 6. Run the setup
./server-setup.sh
```

The `age-key-setup.sh` script will automatically:
- Generate a new Age key pair in `~/.age/keys.txt`
- Configure SOPS to use your Age public key by creating/updating `.sops.yaml`
- Set up the necessary environment variable (`SOPS_AGE_KEY_FILE`)
- Provide instructions for next steps

### Additional Server Setup (Using Existing Configuration)

If you already have an encrypted `private.yml` in your repository:

```bash
# 1. Clone this repository
git clone https://github.com/yourusername/UbuntuServerSetup.git
cd UbuntuServerSetup

# 2. Make all scripts executable
chmod +x *.sh scripts/*.sh

# 3. Run the bootstrap script to install prerequisites (including Age)
./bootstrap.sh

# 4. Export your Age key from your original machine
# On your original machine:
./age-key-setup.sh export
# This creates age-key-export.txt - transfer this file securely to your new server

# 5. Import your Age key on the new server
./age-key-setup.sh import age-key-export.txt
# This will automatically configure SOPS and set up environment variables

# 6. Run the setup directly
./server-setup.sh
```

Alternatively, if you prefer to manually copy your key:

```bash
# Create the Age directory
mkdir -p ~/.age
chmod 700 ~/.age

# Copy your Age key content
nano ~/.age/keys.txt  # paste your Age key here
chmod 600 ~/.age/keys.txt

# Run the Age key setup to configure SOPS with your existing key
./age-key-setup.sh config
./age-key-setup.sh env
```

## Setup Process

### 1. Bootstrap

The bootstrap script prepares your system with the essential tools needed before running the main setup:

```bash
./bootstrap.sh
```

This script:
- Checks for required tools (git, curl, unzip, sops, yq, age, etc.)
- Installs any missing prerequisites
- Works on Ubuntu server installations

### 2. Secret Management

Before running the main setup, you need to create or import your private configuration settings.

#### Initial Configuration

Create your initial encrypted `private.yml` file:

```bash
# Create and encrypt your private configuration
./manage-secrets.sh init
```

This will:
1. Copy the `private.example.yml` template
2. Open it in your default editor
3. Encrypt it with SOPS and Age after saving

#### Working with Encrypted Configuration

The private configuration workflow is similar to ansible-vault - the unencrypted version never persists on disk outside of temporary files during editing.

```bash
# Edit your encrypted configuration
./manage-secrets.sh edit

# View the decrypted content without saving to disk
./manage-secrets.sh view

# Validate YAML syntax
./manage-secrets.sh validate
```

### 3. SSH and GitHub Setup

The setup script automatically:
- Generates an SSH key if one doesn't exist (based on your configuration)
- Uploads the SSH key to GitHub if configured (requires GitHub token)
- Tests the SSH connection to GitHub

### 4. Docker Repository Setup

The setup also:
- Clones your Docker configuration repository from GitHub
- Checks out the specified branch
- Updates the repository if it already exists (when auto_update is enabled)

### 5. Network Mounts

Network mounts defined in your configuration are:
- Added to /etc/fstab for persistence
- Target directories are created with the correct permissions
- Mount options are configured according to your settings

## Using Existing Encrypted Configuration

If you're setting up on a new server and already have an encrypted `private.yml` file in your repository, follow these steps:

### 1. Ensure You Have the Age Private Key

You need to have the Age private key that corresponds to one of the public keys in `.sops.yaml`. This key is typically stored in `~/.age/keys.txt` and looks like:

```
# created: yyyy-mm-ddThh:mm:ss-00:00
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### 2. Clone and Bootstrap on New Server

```bash
# Clone your repository
git clone https://github.com/yourusername/UbuntuServerSetup.git
cd UbuntuServerSetup

# Make all scripts executable
chmod +x *.sh scripts/*.sh

# Run bootstrap to install prerequisites
./bootstrap.sh
```

### 3. Set Up Your Age Key

Create the directory and file:

```bash
mkdir -p ~/.age
chmod 700 ~/.age
nano ~/.age/keys.txt  # Paste your Age key here
chmod 600 ~/.age/keys.txt
```

### 4. Run Setup

You can now run the setup directly:

```bash
# Run setup using the existing encrypted configuration
./server-setup.sh
```

Or you can first verify that decryption works:

```bash
# View the decrypted configuration
./manage-secrets.sh view

# Then run setup
./server-setup.sh
```

## Configuration Options

The setup is driven by two configuration files:

### Public Configuration (public.yml)

Contains non-sensitive settings:
- User and home directory preferences
- Logging level

Example:
```yaml
# User and environment settings
# These are auto-detected but can be overridden here
user: ""  # Leave empty to auto-detect (uses current user)
home_dir: ""  # Leave empty to auto-detect (uses current user's home directory)
log_level: "info"
```

### Private Configuration (private.yml)

Contains sensitive information (always encrypted):
- Git user details
- SSH configuration
- GitHub access tokens
- Docker repository details
- Network mount configurations

Example (before encryption):
```yaml
git_user:
  name: "Your Name"
  email: "your.email@example.com"
ssh:
  generate_key: true
  key_type: ed25519
  key_email: "your.email@example.com"
github:
  username: yourusername
  upload_key: true
  access_token: "githubaccesstoken"
  docker_repo:
    url: "git@github.com:yourusername/docker-configs.git"
    branch: "main"
    directory: "/opt/docker-configs"
    auto_update: true
network_mounts:
  - type: nfs
    source: 192.168.1.10:/Media
    target: /media
    options:
      - noauto
      - nofail
      - _netdev
      - soft
      - x-systemd.automount
    permissions:
      mode: "755"
      owner: "yourusername"
      group: "docker"
```

## Scripts

### bootstrap.sh

**Purpose:** Prepares your system by installing all prerequisite tools needed for the server setup.

**Usage:**
```bash
./bootstrap.sh
```

**Description:**
- Installs required tools (git, curl, unzip, sops, age, etc.)
- Upgrades existing tools if they're already installed
- Ensures the system is ready for the main setup script

### age-key-setup.sh

**Purpose:** Generates, manages, and configures Age encryption keys for use with SOPS.

**Usage:**
```bash
./age-key-setup.sh [command]
```

**Commands:**
- `init` - Initialize everything (generate + config + env)
- `generate` - Generate a new Age key pair
- `config` - Update SOPS config with existing key
- `export` - Export key for use on another machine
- `import FILE` - Import key from FILE
- `env` - Setup environment variables
- `help` - Show help message

**Examples:**
```bash
# Generate a new key and configure SOPS (default action)
./age-key-setup.sh

# Export your key to share with another machine
./age-key-setup.sh export

# Import a key from another machine
./age-key-setup.sh import age-key-export.txt

# Update SOPS configuration
./age-key-setup.sh config

# Set up environment variables
./age-key-setup.sh env
```

### manage-secrets.sh

**Purpose:** Manages encrypted configuration files using SOPS and Age.

**Usage:**
```bash
./manage-secrets.sh <command> [file]
```

**Commands:**
- `edit [file]` - Edit the encrypted file (creates if it doesn't exist)
- `view [file]` - View the decrypted contents without saving to disk
- `validate [file]` - Validate YAML syntax
- `init [file]` - Initialize from example file
- `encrypt <file>` - Encrypt a file in-place (replaces plaintext with encrypted version)
- `rekey <key>` - Add a new public key and re-encrypt (for multi-machine setup)
- `reencrypt` - Re-encrypt file after removing keys from .sops.yaml

### server-setup.sh

**Purpose:** Main setup script that configures your Ubuntu server.

**Usage:**
```bash
./server-setup.sh
```

**Description:**
- Loads and decrypts your configuration files
- Installs and configures Docker and Docker Compose
- Sets up SSH keys and GitHub integration
- Clones your Docker configuration repository
- Configures network mounts
- Extends sudo timeout for the duration of the script

## Security

This project uses several security best practices:

1. **Encrypted Configuration:** Sensitive data is stored in an encrypted state
2. **SOPS with Age:** Modern encryption that's easier to use than GPG
3. **SSH Key Management:** Secure generation and handling of SSH keys
4. **GitHub Token Storage:** Access tokens are stored only in encrypted form
5. **No Plaintext Persistence:** Unencrypted configuration never persists on disk

## Troubleshooting

If you encounter issues:

1. Check the logs for error messages
2. Increase logging verbosity:
   ```yaml
   # In public.yml
   log_level: "debug"
   ```
3. Ensure all prerequisites are installed:
   ```bash
   ./bootstrap.sh
   ```
4. Verify your Age key is properly set up:
   ```bash
   cat ~/.age/keys.txt
   export SOPS_AGE_KEY_FILE=~/.age/keys.txt
   ```
5. Validate your configuration:
   ```bash
   ./manage-secrets.sh validate
   ```
6. For Docker issues, check Docker service status:
   ```bash
   sudo systemctl status docker
   ```
7. For network mount issues, check the mount points:
   ```bash
   df -h
   cat /etc/fstab
   ```