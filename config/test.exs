import Config

config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
  database: "ergon_internal_docs_test",
  hostname: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PORT") || "30003"),
  username: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_USER") || "postgres",
  password: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PASSWORD") || "postgres",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
