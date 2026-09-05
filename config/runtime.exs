import Config

# Database overrides evaluated at BOOT with the launchd environment (plist).
# NOTE: config.exs env reads are baked into sys.config at BUILD time — the boot
# override here is the only place launchd env can take effect (2026-09-05:
# the wrong key names meant the override never fired and prod ran the baked
# default "ergon_internal_docs_dev", which does not exist → pool-wide
# invalid_catalog_name / PgBouncer 08P01 crash-loop).
# Key chain per RuntimeDbConfig convention: <PREFIX>_DB_* → DATABASE_*.
# Prefix = service name "internal_docs_bot".
prefix = "BOT_ARMY_INTERNAL_DOCS_BOT"

db_name = System.get_env("#{prefix}_DB_NAME") || System.get_env("DATABASE_NAME")

if db_name do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    database: db_name,
    hostname:
      System.get_env("#{prefix}_DB_HOST") || System.get_env("DATABASE_HOST") || "127.0.0.1",
    port:
      (System.get_env("#{prefix}_DB_PORT") || System.get_env("DATABASE_PORT") || "30006")
      |> String.to_integer(),
    username: System.get_env("#{prefix}_DB_USER") || System.get_env("DATABASE_USER"),
    password: System.get_env("#{prefix}_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD")
end

# Default doc sources from env (JSON array)
if System.get_env("BOT_ARMY_INTERNAL_DOCS_DEFAULT_SOURCES") do
  case Jason.decode(System.get_env("BOT_ARMY_INTERNAL_DOCS_DEFAULT_SOURCES")) do
    {:ok, sources} when is_list(sources) ->
      config :bot_army_internal_docs, :default_sources, sources

    _ ->
      :ok
  end
end

if System.get_env("BOT_ARMY_INTERNAL_DOCS_PARA_PATH") do
  config :bot_army_internal_docs,
         :para_docs_path,
         System.get_env("BOT_ARMY_INTERNAL_DOCS_PARA_PATH")
end

# Graph database configuration at runtime (postgres-age, port 30002)
config :bot_army_internal_docs, BotArmyInternalDocs.GraphRepo,
  hostname: System.get_env("BOT_ARMY_INTERNAL_DOCS_GRAPHDB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_INTERNAL_DOCS_GRAPHDB_PORT", "30002")),
  username: System.get_env("BOT_ARMY_INTERNAL_DOCS_GRAPHDB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_INTERNAL_DOCS_GRAPHDB_PASSWORD", "postgres"),
  database: System.get_env("BOT_ARMY_INTERNAL_DOCS_GRAPHDB_NAME", "ergon_graphdb_internal_docs"),
  pool_size: System.get_env("BOT_POOL_SIZE", "10") |> String.to_integer()
