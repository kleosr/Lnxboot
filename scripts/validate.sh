#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

validate_function_sizes() {
    local max_lines=40
    local violations=0
    
    echo "Validating function sizes (max ${max_lines} lines)..."
    
    for file in "$LIB_DIR"/*.sh "$PROJECT_ROOT"/Lnxboot.sh; do
        local func_name=""
        local func_start=0
        local line_num=0
        
        while IFS= read -r line; do
            ((line_num++))
            
            if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\(\) ]]; then
                if [ -n "$func_name" ] && [ "$func_start" -gt 0 ]; then
                    local func_lines=$((line_num - func_start - 1))
                    if [ "$func_lines" -gt "$max_lines" ]; then
                        echo "ERROR: Function $func_name in $(basename "$file") exceeds ${max_lines} lines (${func_lines} lines)"
                        ((violations++))
                    fi
                fi
                func_name=$(echo "$line" | sed 's/().*//')
                func_start=$line_num
            elif [[ "$line" =~ ^} ]] && [ -n "$func_name" ]; then
                local func_lines=$((line_num - func_start))
                if [ "$func_lines" -gt "$max_lines" ]; then
                    echo "ERROR: Function $func_name in $(basename "$file") exceeds ${max_lines} lines (${func_lines} lines)"
                    ((violations++))
                fi
                func_name=""
                func_start=0
            fi
        done < "$file"
    done
    
    if [ "$violations" -eq 0 ]; then
        echo "All functions are within size limits"
        return 0
    else
        echo "Found $violations function size violations"
        return 1
    fi
}

validate_constants() {
    echo "Validating constants usage..."
    local violations=0
    
    local magic_numbers=(
        "sleep [0-9]"
        "umask [0-9]"
        "head -[0-9]"
    )
    
    for pattern in "${magic_numbers[@]}"; do
        if grep -r "$pattern" "$LIB_DIR" "$PROJECT_ROOT"/Lnxboot.sh 2>/dev/null | grep -v "API.md" | grep -v "config.sh" | grep -v "GRUB_CUSTOM_FILE_HEADER_LINES\|GRUB_BOOTMGR_ERROR_SLEEP_SEC\|FILESYSTEM_SYNC_SLEEP_SEC\|LOG_FILE_UMASK"; then
            echo "WARNING: Potential magic number found: $pattern"
            ((violations++))
        fi
    done
    
    if [ "$violations" -eq 0 ]; then
        echo "No magic numbers found"
        return 0
    else
        return 1
    fi
}

validate_no_eval() {
    echo "Validating no eval usage..."
    
    if grep -r "eval" "$LIB_DIR" "$PROJECT_ROOT"/Lnxboot.sh 2>/dev/null | grep -v "API.md"; then
        echo "ERROR: eval found in code (security risk)"
        return 1
    fi
    
    echo "No eval usage found"
    return 0
}

validate_syntax() {
    echo "Validating syntax..."
    local errors=0
    
    for file in "$LIB_DIR"/*.sh "$PROJECT_ROOT"/Lnxboot.sh; do
        if ! bash -n "$file" 2>&1; then
            echo "ERROR: Syntax error in $file"
            ((errors++))
        fi
    done
    
    if [ "$errors" -eq 0 ]; then
        echo "All files have valid syntax"
        return 0
    else
        return 1
    fi
}

main() {
    local exit_code=0
    
    validate_syntax || exit_code=1
    validate_function_sizes || exit_code=1
    validate_constants || exit_code=1
    validate_no_eval || exit_code=1
    
    if [ "$exit_code" -eq 0 ]; then
        echo "All validations passed"
    else
        echo "Some validations failed"
    fi
    
    exit $exit_code
}

main "$@"

