import Config

# Database name override from environment
if System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_NAME") do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    database: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_NAME")
end

if System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_HOST") do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    hostname: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_HOST")
end

if System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PORT") do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    port: String.to_integer(System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PORT"))
end

if System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_USER") do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    username: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_USER")
end

if System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PASSWORD") do
  config :bot_army_internal_docs, BotArmyInternalDocs.Repo,
    password: System.get_env("BOT_ARMY_INTERNAL_DOCS_DB_PASSWORD")
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
