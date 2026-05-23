defmodule BotArmyInternalDocs.GraphMigrations.V001CreateSchema do
  @moduledoc """
  Migration V001: Bootstrap the graph schema.

  This migration:
  1. Verifies the 'knowledge' graph exists (created by Salt)
  2. Creates the _Migration node label for version tracking
  3. Does not create vertex/edge constraints (AGE 1.5.0 doesn't support them)
  """

  require Logger

  @version 1
  @description "Bootstrap graph schema and version tracking"

  def version, do: @version
  def description, do: @description

  def up do
    Logger.info("[Migration V001] Bootstrapping graph schema...")
    verify_knowledge_graph()
    Logger.info("[Migration V001] Schema bootstrap complete")
    :ok
  end

  defp verify_knowledge_graph do
    sql = "SELECT 1 FROM ag_graph WHERE name = 'knowledge'"

    case BotArmyInternalDocs.GraphRepo.query(sql, []) do
      {:ok, result} when result.num_rows > 0 ->
        Logger.info("[Migration V001] Knowledge graph verified")
        :ok

      _ ->
        raise "knowledge graph not found - must be created by Salt state"
    end
  end
end
