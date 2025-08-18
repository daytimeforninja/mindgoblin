# Mind Goblin (mg) - Makefile
# Uses nix devshell for all operations

.PHONY: build test clean sync push pull init stats watch help install

# Default target
help:
	@echo "Mind Goblin (mg) - Makefile"
	@echo ""
	@echo "Build targets:"
	@echo "  build     - Build the project"
	@echo "  test      - Run all tests"
	@echo "  clean     - Clean build artifacts"
	@echo "  install   - Install mg binary to ~/.local/bin"
	@echo ""
	@echo "Usage targets:"
	@echo "  sync      - Sync tasks with CalDAV (default: ~/todo.txt)"
	@echo "  push      - Push tasks to CalDAV only"
	@echo "  pull      - Pull completions from CalDAV only"
	@echo "  init      - Initialize mg configuration"
	@echo "  stats     - Show task statistics"
	@echo "  watch     - Auto-sync on file changes (not implemented)"
	@echo ""
	@echo "Options:"
	@echo "  FILE=path - Use custom todo.txt file"
	@echo "  DRY=1     - Dry run mode"
	@echo ""
	@echo "Examples:"
	@echo "  make sync                    # Sync ~/todo.txt"
	@echo "  make sync FILE=work.txt      # Sync custom file"
	@echo "  make push DRY=1              # Dry run push"

# Build targets
build:
	nix develop --command cabal build

test:
	nix develop --command cabal test

clean:
	nix develop --command cabal clean

install: build
	@mkdir -p ~/.local/bin
	nix develop --command cabal install --installdir=~/.local/bin --overwrite-policy=always
	@echo "✅ mg installed to ~/.local/bin/mg"
	@echo "   Make sure ~/.local/bin is in your PATH"

# Usage targets with optional FILE and DRY parameters
sync:
	nix develop --command cabal run mg -- sync $(if $(FILE),--file $(FILE)) $(if $(DRY),--dry-run)

push:
	nix develop --command cabal run mg -- push $(if $(FILE),--file $(FILE)) $(if $(DRY),--dry-run)

pull:
	nix develop --command cabal run mg -- pull $(if $(FILE),--file $(FILE)) $(if $(DRY),--dry-run)

init:
	nix develop --command cabal run mg -- init

stats:
	nix develop --command cabal run mg -- stats $(if $(FILE),--file $(FILE))

watch:
	nix develop --command cabal run mg -- watch $(if $(FILE),--file $(FILE))

# Convenience targets for common workflows
test-sync:
	make sync DRY=1

test-push:
	make push DRY=1

# Development targets
lint:
	nix develop --command hlint src/ test/

format:
	nix develop --command fourmolu -i src/ test/

check: test lint
	@echo "✅ All checks passed"

# Quick test with your actual todo.txt
quick-test:
	@echo "🧠 Testing mg with your current todo.txt..."
	make sync DRY=1
	@echo ""
	@echo "📊 Your current task stats:"
	make stats