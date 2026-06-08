import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console],
  default_formatter: {BotArmyRuntime.LoggerFormatter, []}

config :logger, :console,
  format: {BotArmyRuntime.LoggerFormatter, []},
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

# Primary database (pgvector on port 30003)
config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
  types: BotArmyInternalDocs.PostgrexTypes,
  database: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_NAME") || "ergon_internal_docs_dev",
  hostname: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PORT") || "30003"),
  username: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_USER") || "postgres",
  password: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PASSWORD") || "postgres",
  pool_size: 10

# Default doc sources (JSON from env, or empty)
config :bot_army_internal_docs, :default_sources, []
config :bot_army_internal_docs, :para_docs_path, "docs/personal_os"

if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end

