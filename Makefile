SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)
MIX ?= /Users/abby/.local/share/mise/shims/mix

.PHONY: setup help deps test test-schemas test-stores test-nats test-integration test-full credo dialyzer coverage check format clean release publish-release setup-hooks setup-db reset-db logs status push-and-publish ingestion-progress ingestion-refresh ingestion-status ingestion-watch bump-version compile push git-push pre-push-cleanup sync-release-version

help:
	@echo "Internal Docs Bot"
	@echo ""
	@echo "Setup commands:"
	@echo "  make setup           - Set up project (deps.get + install git hooks + setup database)"
	@echo "  make setup-hooks     - Install git hooks for pre-push validation"
	@echo "  make setup-db        - Create and migrate database"
	@echo "  make reset-db        - Drop and recreate database"
	@echo ""
	@echo "Development commands:"
	@echo "  make test            - Run all tests (excludes integration)"
	@echo "  make test-schemas    - Run schema tests only"
	@echo "  make test-stores     - Run store tests only"
	@echo "  make test-nats       - Run NATS tests only"
	@echo "  make test-integration- Run integration tests (requires DB)"
	@echo "  make test-full       - Run all tests including integration"
	@echo "  make credo           - Run linter"
	@echo "  make dialyzer        - Run static analysis"
	@echo "  make coverage        - Run tests with coverage"
	@echo "  make check           - Run all checks (test, credo, dialyzer)"
	@echo "  make format          - Format Elixir code"
	@echo "  make clean           - Clean build artifacts"
	@echo ""
	@echo "Operations:"
	@echo "  make logs            - Tail server log"
	@echo "  make status          - Check if bot is running"
	@echo ""
	@echo "Ingestion & Document Management:"
	@echo "  make ingestion-progress  - Show document embedding progress"
	@echo "  make ingestion-status    - List configured doc sources and chunk counts"
	@echo "  make ingestion-refresh   - Manually trigger document re-fetch and indexing"
	@echo "  make ingestion-watch     - Watch ingestion activity (tail logs)"
	@echo ""
	@echo "Release commands:"
	@echo "  make release         - Build OTP release locally"
	@echo "  make publish-release - Build, package, and publish to GitHub"
	@echo ""

setup: init deps setup-hooks setup-db
	@echo "Setup complete!"

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "Git hooks installed"

setup-db:
	@echo "Setting up database..."
	@MIX_ENV=test $(MIX) ecto.create || true
	@MIX_ENV=test $(MIX) ecto.migrate
	@echo "Database ready"

reset-db:
	@echo "Resetting database..."
	@MIX_ENV=test $(MIX) ecto.drop || true
	@MIX_ENV=test $(MIX) ecto.create
	@MIX_ENV=test $(MIX) ecto.migrate
	@echo "Database reset"

init:
	@if [ ! -d .git ]; then git init; fi

_compile-impl:
	@LOG_FILE="/tmp/compile-docs-$$(date +%s).log"; \
	echo "Compiling docs and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

deps:
	$(MIX) deps.get

_compile-impl:
	@LOG_FILE="/tmp/compile-docs-$$(date +%s).log"; \
	echo "Compiling docs and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

test:
	$(MIX) test

test-schemas:
	$(MIX) test --only schemas --trace

test-stores:
	$(MIX) test --only stores --trace

test-nats:
	$(MIX) test --only nats --trace

test-integration:
	$(MIX) test --include integration --trace

test-full:
	$(MIX) test --include integration --include nats_live --trace

credo:
	$(MIX) credo --only warning

dialyzer: deps
	$(MIX) dialyzer

coverage:
	$(MIX) coveralls

check: test credo
	@echo "All checks passed!"

format:
	$(MIX) format

clean:
	$(MIX) clean
	rm -rf _build cover

release: check
	@echo "Building OTP release..."
	rm -rf _build/prod/rel/internal_docs_bot
	MIX_ENV=prod $(MIX) release
	@echo "Release built: _build/prod/rel/internal_docs_bot/"

publish-release: release
	@set -e; \
	VERSION=$$(sed -n 's/^[[:space:]]*version:[[:space:]]*"\([^"]*\)".*/\1/p' mix.exs | head -n 1); \
	if [ -z "$$VERSION" ]; then \
		echo "Failed to resolve version from mix.exs"; \
		exit 1; \
	fi; \
	TARBALL=internal_docs_bot-$$VERSION.tar.gz; \
	echo "Version: $$VERSION"; \
	echo "Creating release tarball..."; \
	tar -czf "$$TARBALL" -C _build/prod/rel internal_docs_bot/; \
	echo "✓ Tarball created: $$TARBALL"; \
	echo ""; \
	echo "Creating GitHub release v$$VERSION..."; \
	if gh release view "v$$VERSION" >/dev/null 2>&1; then \
		gh release upload "v$$VERSION" "$$TARBALL" --clobber; \
	else \
		gh release create "v$$VERSION" "$$TARBALL" \
			--title "Release v$$VERSION" \
			--notes "Internal Docs Bot Elixir release v$$VERSION. Download and deploy with Jenkins." \
			--draft=false; \
	fi; \
	echo "✓ Release published to GitHub"; \
	echo "" 
push-and-publish:
	@git push && $(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh

status:
	@ps aux | grep beam | grep internal_docs | grep -v grep || echo "Bot not running"

ingestion-progress:
	@$(MIX) run scripts/ingestion_progress.exs

ingestion-status:
	@$(MIX) run scripts/ingestion_status.exs

ingestion-refresh:
	@$(MIX) run scripts/ingestion_refresh.exs

ingestion-watch:
	@echo "👀 Watching ingestion activity (Ctrl+C to stop)..."
	@echo ""
	@tail -f /var/log/bot_army/internal_docs.log 2>/dev/null | grep -E "\[Poller\]|\[Chunker\]|\[EmbedWorker\]|chunk|embed|Fetching|Published" || echo "Log file not found"

bump-version:
	@if [ -z "$(BUMP)" ]; then echo "Usage: make bump-version BUMP=major|minor|patch"; exit 1; fi
	@OLD=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	bash $(SCRIPTS_DIRECTORY)/bump_version.sh mix.exs $(BUMP) > /dev/null; \
	NEW=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	echo "✓ Bumped: $$OLD → $$NEW"

push: test compile credo
	@echo "✅ All validations passed"
	@echo "$$(date +%s)" > .push-validated
	@echo "✓ Proof-of-validation created"
	@$(MAKE) git-push


git-push:
	@git push origin main 2>&1 | tail -3

# Shared targets (push, credo, pre-push-cleanup, bump-version, git-push).
# Defined once in bot_army_infra so they cannot drift per repo.
BOT_ARMY_COMMON_MK := $(abspath $(CURDIR)/../bot_army_infra/make/common.mk)
ifeq ($(wildcard $(BOT_ARMY_COMMON_MK)),)
$(warning bot_army_infra not found at $(BOT_ARMY_COMMON_MK) - shared targets unavailable)
else
include $(BOT_ARMY_COMMON_MK)
endif
