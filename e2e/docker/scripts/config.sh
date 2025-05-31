#!/bin/bash

# Central configuration manager for e2e tests
# Source this file in all other scripts instead of reading env files directly

set -euo pipefail

# =============================================================================
# ENVIRONMENT DETECTION AND PATH SETUP
# =============================================================================

# Detect execution context
if [ "${IS_DOCKER:-false}" = "true" ]; then
    # Docker context - all paths must be provided via environment
    E2E_CONFIG_ROOT="/app"
    SCRIPTS_DIR="${SCRIPTS_DIR:?IS_DOCKER is true but SCRIPTS_DIR is not set}"
    ARTIFACTS_DIR="${ARTIFACTS_DIR:?IS_DOCKER is true but ARTIFACTS_DIR is not set}"
    NODES_DIR="${NODES_DIR:?IS_DOCKER is true but NODES_DIR is not set}"
    E2E_ENV_FILE="${E2E_ENV_FILE:?IS_DOCKER is true but E2E_ENV_FILE is not set}"
    FOUNDRY_ROOT_DIR="${FOUNDRY_ROOT_DIR:?IS_DOCKER is true but FOUNDRY_ROOT_DIR is not set}"
else
    # Local context - derive paths from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    E2E_CONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    SCRIPTS_DIR="${SCRIPTS_DIR:-"$SCRIPT_DIR"}"
    ARTIFACTS_DIR="${ARTIFACTS_DIR:-"$E2E_CONFIG_ROOT/../../contracts/artifacts"}"
    NODES_DIR="${NODES_DIR:-"$E2E_CONFIG_ROOT/../../contracts/.nodes"}"
    E2E_ENV_FILE="${E2E_ENV_FILE:-"$E2E_CONFIG_ROOT/../envs/bls-testnet.env"}"
    FOUNDRY_ROOT_DIR="${FOUNDRY_ROOT_DIR:-"$E2E_CONFIG_ROOT/../../contracts"}"
fi

# =============================================================================
# ENVIRONMENT VALIDATION
# =============================================================================

validate_env_file() {
    if [ ! -f "$E2E_ENV_FILE" ]; then
        echo "❌ Error: E2E_ENV_FILE points to non-existent file: $E2E_ENV_FILE" >&2
        exit 1
    fi
    
    if [ ! -r "$E2E_ENV_FILE" ]; then
        echo "❌ Error: E2E_ENV_FILE is not readable: $E2E_ENV_FILE" >&2
        exit 1
    fi
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

load_environment() {
    validate_env_file
    
    # Source the environment file
    set -a  # automatically export all variables
    source "$E2E_ENV_FILE"
    set +a
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Suppress output on success, show on failure when used in pipeline
# Usage: some_command 2>&1 | silent_success
silent_success() {
    local output
    local exit_code
    
    # Read all input and capture it
    output=$(cat)
    exit_code=$?
    
    # Get the exit status of the command that was piped to us
    # Note: PIPESTATUS[0] contains the exit status of the first command in the pipeline
    local pipe_status=${PIPESTATUS[0]:-$exit_code}
    
    # If the previous command failed, show the output to stderr
    if [ "$pipe_status" -ne 0 ]; then
        echo "$output" >&2
        return "$pipe_status"
    fi
    
    # Success - suppress output
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Export path variables
export SCRIPTS_DIR ARTIFACTS_DIR NODES_DIR E2E_ENV_FILE FOUNDRY_ROOT_DIR

# Auto-load environment if this script is sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    load_environment
fi 