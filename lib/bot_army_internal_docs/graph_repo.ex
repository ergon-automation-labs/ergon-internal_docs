defmodule BotArmyInternalDocs.GraphRepo do
  @moduledoc "Ecto repo for Apache AGE graph queries (internal_docs bot)."
  use Ecto.Repo,
    otp_app: :bot_army_internal_docs,
    adapter: Ecto.Adapters.Postgres

  require Logger

  def init(_, opts) do
    opts =
      Keyword.put(opts, :after_connect, fn conn ->
        try do
          Postgrex.query!(conn, "LOAD 'age'", [])
          Postgrex.query!(conn, "SET search_path = ag_catalog, \"$user\", public", [])
        rescue
          e ->
            Logger.warning(
              "[BotArmyInternalDocs.GraphRepo] AGE extension unavailable or error during init: #{inspect(e)}"
            )
        end
      end)

    {:ok, opts}
  end
end
