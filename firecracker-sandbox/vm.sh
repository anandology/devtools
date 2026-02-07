#!/bin/bash

# Main VM CLI dispatcher
# Routes commands to specialized scripts in bin/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

# Source global configuration
source "$BIN_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

usage() {
    cat << EOF
Usage: vm.sh <command> [arguments]

Commands:
  init <name>              Initialize a new VM configuration
  build <name>             Build VM images (requires sudo)
  up <name>                Start a VM
  console <name>           Start a VM with console access
  down <name>              Stop a VM
  ssh <name> [args]        SSH into a running VM
  status <name>            Show VM status
  list                     List all VMs
  doctor                   Diagnose VM environment health
  destroy <name>           Destroy a VM (requires sudo)

Examples:
  vm.sh init myvm
  sudo vm.sh build myvm
  vm.sh up myvm
  vm.sh ssh myvm
  vm.sh down myvm

Global setup (run once):
  sudo bin/setup.sh        Set up bridge network
  sudo bin/cleanup.sh      Remove all VMs and bridge
EOF
    exit 1
}

# Check if command is provided
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

# Route commands to appropriate scripts
case "$COMMAND" in
    init)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh init <name>"
        fi
        exec "$BIN_DIR/vm-init.sh" "$@"
        ;;
    
    build)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: sudo vm.sh build <name>"
        fi
        exec "$BIN_DIR/vm-build.sh" "$@"
        ;;
    
    up)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh up <name>"
        fi
        exec "$BIN_DIR/vm-up.sh" "$@"
        ;;
    
    console)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh console <name>"
        fi
        exec "$BIN_DIR/vm-console.sh" "$@"
        ;;
    
    down)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh down <name>"
        fi
        exec "$BIN_DIR/vm-down.sh" "$@"
        ;;
    
    ssh)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh ssh <name> [ssh-args]"
        fi
        exec "$BIN_DIR/vm-ssh.sh" "$@"
        ;;
    
    status)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: vm.sh status <name>"
        fi
        exec "$BIN_DIR/vm-status.sh" "$@"
        ;;
    
    list)
        exec "$BIN_DIR/vm-list.sh" "$@"
        ;;
    
    doctor)
        exec "$BIN_DIR/vm-doctor.sh" "$@"
        ;;
    
    destroy)
        if [[ $# -lt 1 ]]; then
            error "VM name required. Usage: sudo vm.sh destroy <name>"
        fi
        exec "$BIN_DIR/vm-destroy.sh" "$@"
        ;;
    
    help|--help|-h)
        usage
        ;;
    
    *)
        error "Unknown command: $COMMAND. Run 'vm.sh help' for usage."
        ;;
esac
