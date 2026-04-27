Postgrex.Types.define(
  BotArmyInternalDocs.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
