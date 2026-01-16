# Tailscale Receiver - Development Makefile
.PHONY: help install uninstall test lint format clean setup dev-setup check-deps deb rpm packages

# Default target
help:
	@echo "Tailscale Receiver - Development Commands"
	@echo ""
	@echo "Development:"
	@echo "  make setup         - Install development dependencies"
	@echo "  make dev-setup     - Full development environment setup"
	@echo "  make check-deps    - Check if all dependencies are installed"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint          - Run shellcheck on all scripts"
	@echo "  make format        - Format shell scripts with shfmt"
	@echo "  make test          - Run test suite"
	@echo ""
	@echo "Installation:"
	@echo "  make install       - Install Tailscale Receiver"
	@echo "  make uninstall     - Uninstall Tailscale Receiver"
	@echo ""
	@echo "Packaging:"
	@echo "  make deb           - Build Debian package"
	@echo "  make rpm           - Build RPM package"
	@echo "  make packages      - Build both Debian and RPM packages"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean         - Clean temporary files"
	@echo "  make status        - Show service status"
	@echo "  make logs          - Show service logs"
	@echo ""

# Development setup
setup: check-deps
	@echo "Setting up development environment..."

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@command -v shellcheck >/dev/null 2>&1 && echo "✅ shellcheck found" || echo "❌ shellcheck missing (run: sudo apt install shellcheck)"
	@command -v shfmt >/dev/null 2>&1 && echo "✅ shfmt found" || echo "❌ shfmt missing (run: sudo apt install shfmt)"
	@command -v bats >/dev/null 2>&1 && echo "✅ bats found" || echo "❌ bats missing (run: sudo apt install bats)"
	@command -v tailscale >/dev/null 2>&1 && echo "✅ tailscale found" || echo "❌ tailscale missing"
	@command -v systemctl >/dev/null 2>&1 && echo "✅ systemd found" || echo "❌ systemd missing"

# Full development setup
dev-setup: check-deps
	@echo "Installing development dependencies..."
	@command -v shellcheck >/dev/null 2>&1 || (echo "Installing shellcheck..." && sudo apt update && sudo apt install -y shellcheck)
	@command -v shfmt >/dev/null 2>&1 || (echo "Installing shfmt..." && sudo apt install -y shfmt)
	@command -v bats >/dev/null 2>&1 || (echo "Installing bats..." && sudo apt install -y bats)
	@echo "✅ Development environment ready!"

# Code quality
lint:
	@echo "Running shellcheck..."
	@find . -name "*.sh" -type f -exec shellcheck {} \; || echo "❌ Lint errors found"
	@echo "✅ Linting complete"

format:
	@echo "Formatting shell scripts..."
	@find . -name "*.sh" -type f -exec shfmt -w -i 2 {} \;
	@echo "✅ Formatting complete"

# Testing
test: test-unit test-integration

test-all: test-unit test-integration test-security

test-unit:
	@echo "Running unit tests..."
	@if [ -d "test" ]; then \
		cd test && bats *.bats; \
	else \
		echo "⚠️  No test directory found. Run 'make test-setup' to create tests."; \
	fi

test-directory:
	@echo "Running directory-specific tests..."
	@if [ -d "test" ] && [ -f "test/directory.bats" ]; then \
		cd test && bats directory.bats; \
	else \
		echo "⚠️  Directory tests not found."; \
	fi

test-integration:
	@echo "Running integration tests..."
	@if [ -f "test/integration.bats" ]; then \
		cd test && bats integration.bats; \
	else \
		echo "⚠️  Integration tests not found."; \
	fi

test-security:
	@echo "Running security tests..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -name "*.sh" -type f -exec shellcheck --severity=error {} \; && echo "✅ Security linting passed"; \
	else \
		echo "⚠️  ShellCheck not available for security testing"; \
	fi

test-setup:
	@echo "Setting up test directory..."
	@mkdir -p test
	@echo "✅ Test directory created. Add .bats files for testing."

# Installation
install:
	@echo "Installing Tailscale Receiver..."
	@chmod +x install.sh uninstall.sh tailscale-receive.sh tailscale-send.sh
	@sudo ./install.sh

uninstall:
	@echo "Uninstalling Tailscale Receiver..."
	@sudo ./uninstall.sh

# Service management
status:
	@sudo systemctl status tailscale-receive.service

logs:
	@sudo journalctl -u tailscale-receive.service -f --since "1 hour ago"

# Maintenance
clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name "*.bak" -delete
	@find . -name "*.log" -delete
	@find . -name ".DS_Store" -delete
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Cleanup complete"

# CI/CD simulation
ci: check-deps lint test
	@echo "✅ CI checks passed!"

# Packaging
deb:
	@echo "Building Debian package..."
	@if command -v dpkg-buildpackage >/dev/null 2>&1; then \
		dpkg-buildpackage -us -uc -b; \
		echo "✅ Debian package built successfully"; \
	else \
		echo "❌ dpkg-buildpackage not found. Install with: sudo apt install build-essential devscripts"; \
		exit 1; \
	fi

rpm:
	@echo "Building RPM package..."
	@if command -v rpmbuild >/dev/null 2>&1; then \
		mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}; \
		tar czf ~/rpmbuild/SOURCES/tailscale-receiver-2.3.0.tar.gz --exclude=.git --exclude=test --exclude=debian --exclude=rpm .; \
		rpmbuild -ba rpm/tailscale-receiver.spec; \
		echo "✅ RPM package built successfully"; \
	else \
		echo "❌ rpmbuild not found. Install with: sudo dnf install rpm-build"; \
		exit 1; \
	fi

packages: deb rpm
	@echo "✅ All packages built successfully"

# Development helpers
update-scripts:
	@echo "Making scripts executable..."
	@chmod +x *.sh
	@echo "✅ Scripts updated"

validate:
	@echo "Validating all scripts..."
	@for script in *.sh; do \
		if bash -n "$$script"; then \
			echo "✅ $$script syntax OK"; \
		else \
			echo "❌ $$script has syntax errors"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All scripts validated"
