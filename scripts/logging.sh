#!/usr/bin/env bash
# =================================================================
# Logging Module for Ubuntu Server Setup
# =================================================================
# This module provides consistent logging functions for all scripts.
# Source this file in other scripts to use these functions.
# =================================================================

# Colors for output
export LOG_GREEN='\033[0;32m'
export LOG_YELLOW='\033[1;33m'
export LOG_RED='\033[0;31m'
export LOG_BLUE='\033[0;34m'
export LOG_MAGENTA='\033[0;35m'
export LOG_CYAN='\033[0;36m'
export LOG_NC='\033[0m' # No Color

# Symbols
export LOG_CHECK="✓"
export LOG_CROSS="✗"
export LOG_CIRCLE="○"
export LOG_ARROW="→"

# Logging levels
export LOG_LEVEL_DEBUG=0
export LOG_LEVEL_INFO=1
export LOG_LEVEL_WARN=2
export LOG_LEVEL_ERROR=3

# Default log level
export CURRENT_LOG_LEVEL=${LOG_LEVEL:-${CURRENT_LOG_LEVEL:-$LOG_LEVEL_INFO}}

# Helper functions
log_debug() {
  if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
    echo -e "${LOG_CYAN}[DEBUG]${LOG_NC} $1"
  fi
}

log_info() {
  if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]; then
    echo -e "${LOG_GREEN}[INFO]${LOG_NC} $1"
  fi
}

log_warn() {
  if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_WARN" ]; then
    echo -e "${LOG_YELLOW}[WARNING]${LOG_NC} $1"
  fi
}

log_error() {
  if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]; then
    echo -e "${LOG_RED}[ERROR]${LOG_NC} $1"
  fi
  return 1  # Return error code but don't exit
}

log_fatal() {
  if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]; then
    echo -e "${LOG_RED}[FATAL]${LOG_NC} $1"
  fi
  exit 1
}

# Status checking functions
log_success() {
  echo -e "${LOG_GREEN}${LOG_CHECK}${LOG_NC} $1"
}

log_failure() {
  echo -e "${LOG_RED}${LOG_CROSS}${LOG_NC} $1"
}

log_optional() {
  echo -e "${LOG_YELLOW}${LOG_CIRCLE}${LOG_NC} $1"
}

# Section headers
log_section() {
  echo -e "\n${LOG_BLUE}===== $1 =====${LOG_NC}"
}

log_subsection() {
  echo -e "${LOG_CYAN}--- $1 ---${LOG_NC}"
}

# Set log level
set_log_level() {
  case "$1" in
    debug)
      CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
      ;;
    info)
      CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
      ;;
    warn|warning)
      CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN
      ;;
    error)
      CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR
      ;;
    *)
      log_warn "Unknown log level: $1, using 'info'"
      CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
      ;;
  esac
  log_debug "Log level set to $CURRENT_LOG_LEVEL"
}

# Check if this script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Show usage if run directly
  echo "This is a logging module that should be sourced by other scripts."
  echo "Source this file using: . logging.sh"
  echo "Or: source logging.sh"
  echo ""
  echo "Available functions:"
  echo "  log_debug \"message\"     - Log debug message"
  echo "  log_info \"message\"      - Log info message"
  echo "  log_warn \"message\"      - Log warning message"
  echo "  log_error \"message\"     - Log error message (returns 1)"
  echo "  log_fatal \"message\"     - Log fatal message and exit (exits 1)"
  echo "  log_success \"message\"   - Log success message with checkmark"
  echo "  log_failure \"message\"   - Log failure message with cross"
  echo "  log_optional \"message\"  - Log optional message with circle"
  echo "  log_section \"title\"     - Log section header"
  echo "  log_subsection \"title\"  - Log subsection header"
  echo "  set_log_level <level>     - Set log level (debug|info|warn|error)"
  echo ""
  echo "Log Level Configuration:"
  echo "  1. Set in configuration with 'log_level: \"debug\"'"
  echo "  2. Override with environment variable: LOG_LEVEL=0 ./script.sh"
  echo "  3. Set programmatically: set_log_level debug"
  echo ""
  echo "Example usage:"
  echo "  source logging.sh"
  echo "  log_section \"Starting Process\""
  echo "  log_info \"Processing file...\""
  echo "  log_success \"File processed successfully\""
fi