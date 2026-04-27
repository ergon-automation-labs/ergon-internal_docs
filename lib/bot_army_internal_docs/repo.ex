defmodule BotArmyInternalDocs.Repo do
  use Ecto.Repo,
    otp_app: :bot_army_internal_docs,
    adapter: Ecto.Adapters.Postgres
end
