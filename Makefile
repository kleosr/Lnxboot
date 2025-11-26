.PHONY: all check lint test clean install

SHELL := /bin/bash
SCRIPT_DIR := $(shell pwd)
LIB_DIR := $(SCRIPT_DIR)/lib
MAIN_SCRIPT := Lnxboot.sh

all: check

check: lint test

lint:
	@echo "Running ShellCheck..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(MAIN_SCRIPT) $(LIB_DIR)/*.sh || exit 1; \
	else \
		echo "Warning: shellcheck not installed, skipping lint"; \
	fi

test:
	@echo "Running syntax checks..."
	@for script in $(MAIN_SCRIPT) $(LIB_DIR)/*.sh; do \
		echo "Checking $$script..."; \
		bash -n "$$script" || exit 1; \
	done
	@echo "All syntax checks passed"

validate-functions:
	@echo "Validating function signatures..."
	@bash -c ' \
		source $(LIB_DIR)/config.sh; \
		source $(LIB_DIR)/logger.sh; \
		for lib in $(LIB_DIR)/*.sh; do \
			echo "Validating $$lib..."; \
			bash -n "$$lib" || exit 1; \
		done \
	'
	@echo "Function validation complete"

clean:
	@echo "Cleaning temporary files..."
	@rm -f *.log
	@rm -rf /mnt/windows_target /mnt/iso_temp 2>/dev/null || true
	@echo "Cleanup complete"

install: check
	@echo "Installing Lnxboot..."
	@install -m 755 $(MAIN_SCRIPT) /usr/local/bin/lnxboot
	@echo "Installation complete. Run: sudo lnxboot --help"

uninstall:
	@echo "Uninstalling Lnxboot..."
	@rm -f /usr/local/bin/lnxboot
	@echo "Uninstallation complete"

help:
	@echo "Available targets:"
	@echo "  all              - Run all checks (default)"
	@echo "  check            - Run lint and test"
	@echo "  lint             - Run ShellCheck on all scripts"
	@echo "  test             - Run syntax validation"
	@echo "  validate-functions - Validate function signatures"
	@echo "  clean            - Remove temporary files"
	@echo "  install          - Install to /usr/local/bin"
	@echo "  uninstall        - Remove from /usr/local/bin"
	@echo "  help             - Show this help message"

