#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        log "DEBUG: $1"
    fi
}

log_info() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]; then
        log "INFO: $1"
    fi
}

log_warn() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_WARN" ]; then
        log "WARN: $1" >&2
    fi
}

log_error() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]; then
        log "ERROR: $1" >&2
    fi
}

get_stack_trace() {
    local frame=0
    local result=""
    while caller $frame; do
        result="${result}$(caller $frame)\n"
        ((++frame))
    done
    echo -e "$result"
}

log_error_with_trace() {
    local message="$1"
    log_error "$message"
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        local trace=$(get_stack_trace)
        log_error "Stack trace:\n$trace"
    fi
}

die() {
    local exit_code="${2:-1}"
    log_error_with_trace "$1"
    exit "$exit_code"
}

init_logging() {
    local log_file_path="${1:-$LOG_FILE}"
    LOG_FILE="$log_file_path"
    mkdir -p "$(dirname "$LOG_FILE")"
    umask 077
    touch "$LOG_FILE"
    if [ ! -w "$LOG_FILE" ]; then
        echo "[ERROR] Cannot write to log file: $LOG_FILE" >&2
        exit 1
    fi
}

on_error() {
    local exit_code=$?
    local line_no=${BASH_LINENO[0]:-0}
    local func_name=${FUNCNAME[1]:-main}
    log_error "Command failed with exit code $exit_code at line $line_no in function $func_name: $BASH_COMMAND"
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        local trace=$(get_stack_trace)
        log_error "Stack trace:\n$trace"
    fi
}

setup_error_trap() {
    trap on_error ERR
}
