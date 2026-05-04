SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)
MIX ?= /Users/abby/.local/share/mise/shims/mix

.PHONY: setup help deps test test-schemas test-stores test-nats test-integration test-full \ push-and-publish
       credo dialyzer coverage check format clean release publish-release \
       setup-hooks setup-db reset-db logs status

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

deps:
	$(MIX) deps.get

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
	@echo "Publishing release to GitHub..."
	VERSION=$$(cat _build/prod/rel/internal_docs_bot/releases/RELEASES | tail -1 | cut -d' ' -f2); \
	echo "Version: $$VERSION"; \
	tar -czf internal_docs_bot-$$VERSION.tar.gz -C _build/prod/rel internal_docs_bot/; \
	gh release create v$$VERSION internal_docs_bot-$$VERSION.tar.gz \
		--title "Release v$$VERSION" \
		--notes "Internal Docs Bot release v$$VERSION" \
		--draft=false; \
	echo "Release published"

push-and-publish:
	@git push && $(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh

status:
	@ps aux | grep beam | grep internal_docs | grep -v grep || echo "Bot not running"
