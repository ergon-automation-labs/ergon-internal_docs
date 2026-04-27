SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)

.PHONY: setup help deps test test-schemas test-stores test-nats test-integration test-full \
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
	@echo "Release commands (normally automatic via git hook):"
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
	@MIX_ENV=test mix ecto.create || true
	@MIX_ENV=test mix ecto.migrate
	@echo "Database ready"

reset-db:
	@echo "Resetting database..."
	@MIX_ENV=test mix ecto.drop || true
	@MIX_ENV=test mix ecto.create
	@MIX_ENV=test mix ecto.migrate
	@echo "Database reset"

init:
	@if [ ! -d .git ]; then git init; fi

deps:
	mix deps.get

test:
	mix test

test-schemas:
	mix test --only schemas --trace

test-stores:
	mix test --only stores --trace

test-nats:
	mix test --only nats --trace

test-integration:
	mix test --include integration --trace

test-full:
	mix test --include integration --include nats_live --trace

credo:
	mix credo

dialyzer: deps
	mix dialyzer

coverage:
	mix coveralls

check: test credo dialyzer
	@echo "All checks passed!"

format:
	mix format

clean:
	mix clean
	rm -rf _build cover

release: check
	@echo "Building OTP release..."
	MIX_ENV=prod mix release --overwrite
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

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh

status:
	@ps aux | grep beam | grep internal_docs | grep -v grep || echo "Bot not running"