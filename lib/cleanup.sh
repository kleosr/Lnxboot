#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

cleanup() {
    if [ -n "${LOG_FILE:-}" ]; then
        log_info "Cleaning up mount points..."
    fi
    umount "${ISO_MOUNT:-}" 2>/dev/null || true
    umount "${MOUNT_POINT:-}" 2>/dev/null || true
    rm -rf "${ISO_MOUNT:-}" "${MOUNT_POINT:-}" 2>/dev/null || true
    if [ -n "${LOG_FILE:-}" ]; then
        log_info "Cleanup completed."
    fi
}

setup_cleanup_trap() {
    trap cleanup EXIT
}

