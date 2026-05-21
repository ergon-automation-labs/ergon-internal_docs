#!/usr/bin/env elixir

IO.puts("🔄 Triggering document fetch and indexing...")
BotArmyInternalDocs.Ingestion.Poller.run_fetch()
IO.puts("✓ Fetch triggered. Check logs for progress:")
IO.puts("   make ingestion-watch")
