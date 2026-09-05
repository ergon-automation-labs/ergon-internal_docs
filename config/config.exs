import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "[$time] [$level] $message\n",
  metadata: [:correlation_id]

# Load .env for local development
if File.exists?("config/.env") or File.exists?(".env") do
  path = if File.exists?("config/.env"), do: "config/.env", else: ".env"

  File.stream!(path)
  |> Stream.map(&String.trim_trailing/1)
  |> Stream.reject(&String.starts_with?(&1, "#"))
  |> Stream.reject(&(&1 == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(key, value)
      _ -> nil
    end
  end)
end

config :bot_army_internal_docs,
  ecto_repos: [BotArmyInternalDocs.Repo, BotArmyInternalDocs.GraphRepo]

# Configure library graph functions to use this bot's repo
config :bot_army_library_core, :graph_repo, BotArmyInternalDocs.GraphRepo

# Primary database (pgvector; LaunchDaemon env via PgBouncer 30006)
config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
  types: BotArmyInternalDocs.PostgrexTypes,
  # Runtime convention (RuntimeDbConfig.resolve): <PREFIX>_DB_NAME -> DATABASE_NAME -> dev default.
  # Prefix = service name "internal_docs_bot": the old key here was missing the _BOT_
  # segment, so prod fell back to the non-existent ergon_internal_docs_dev and every
  # pool connection failed (invalid_catalog_name, 2026-09-05).
  database:
    System.get_env("BOT_ARMY_INTERNAL_DOCS_BOT_DB_NAME") ||
      System.get_env("DATABASE_NAME") || "ergon_internal_docs_dev",
  hostname: System.get_env("BOT_ARMY_INTERNAL_DOCS_BOT_DB_HOST") || "127.0.0.1",
  port: String.to_integer(System.get_env("BOT_ARMY_INTERNAL_DOCS_BOT_DB_PORT") || "30006"),
  username: System.get_env("BOT_ARMY_INTERNAL_DOCS_BOT_DB_USER") || "postgres",
  password: System.get_env("BOT_ARMY_INTERNAL_DOCS_BOT_DB_PASSWORD") || "postgres",
  pool_size: 10

# Default doc sources (JSON from env, or empty)
config :bot_army_internal_docs, :default_sources, []
config :bot_army_internal_docs, :para_docs_path, "docs/personal_os"

if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end

