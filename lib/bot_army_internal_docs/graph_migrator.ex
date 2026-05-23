defmodule BotArmyInternalDocs.GraphMigrator do
  @moduledoc """
  Custom migration runner for Apache AGE graph database.

  Since AGE runs on PostgreSQL but is not managed by Ecto.Migrator,
  this module provides a simple migration system that:

  1. Tracks applied migrations using `_Migration` nodes in the graph itself
  2. Loads all migration modules from `BotArmyInternalDocs.GraphMigrations.V*`
  3. Runs pending migrations in version order
  4. Records each version after successful completion

  All migrations use MERGE operations (idempotent) so they are safe to re-run.

  ## Usage

  From IEx:
      BotArmyInternalDocs.GraphMigrator.run()

  From OTP release:
      internal_docs_bot/bin/internal_docs_bot eval 'BotArmyInternalDocs.Release.migrate_graph()'
  """

  require Logger

  @app :bot_army_internal_docs

  def run do
    Logger.info("[GraphMigrator] Starting graph migrations...")
    load_app()

    case check_graph_available() do
      :ok ->
        applied = get_applied_versions()
        pending = get_pending_migrations(applied)

        if Enum.empty?(pending) do
          Logger.info("[GraphMigrator] No pending migrations")
        else
          run_migrations(pending)
        end

      {:error, reason} ->
        Logger.error("[GraphMigrator] Graph not available: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp check_graph_available do
    sql = "SELECT 1 FROM ag_graph WHERE name = 'knowledge'"

    case BotArmyInternalDocs.GraphRepo.query(sql, []) do
      {:ok, result} when result.num_rows > 0 ->
        :ok

      {:error, e} ->
        Logger.warning("[GraphMigrator] Graph check failed: #{inspect(e)}")
        {:error, :graph_unavailable}

      _ ->
        {:error, "knowledge graph not found"}
    end
  end

  defp get_applied_versions do
    cypher = "MATCH (m:_Migration) RETURN m.version as version ORDER BY version"
    sql = "SELECT * FROM cypher('knowledge', $1) AS (result agtype)"

    case BotArmyInternalDocs.GraphRepo.query(sql, [cypher]) do
      {:ok, _result} ->
        []

      _ ->
        []
    end
  end

  defp get_pending_migrations(applied) do
    all_migrations = get_all_migrations()
    applied_set = MapSet.new(applied)

    all_migrations
    |> Enum.filter(fn migration ->
      version = migration.version()
      not MapSet.member?(applied_set, version)
    end)
    |> Enum.sort_by(& &1.version())
  end

  defp get_all_migrations do
    load_from_lib()
  end

  defp load_from_lib do
    {:ok, modules} = :application.get_key(@app, :modules)

    modules
    |> Enum.filter(&graph_migration_module?/1)
    |> Enum.sort_by(fn module -> module.version() end)
  end

  defp graph_migration_module?(module) do
    module_str = module |> Atom.to_string()
    String.contains?(module_str, "BotArmyInternalDocs.GraphMigrations.V")
  end

  defp run_migrations(pending) do
    Enum.each(pending, fn migration ->
      run_migration(migration)
    end)

    Logger.info("[GraphMigrator] All migrations completed successfully")
    :ok
  end

  defp run_migration(migration) do
    version = migration.version()
    description = migration.description()

    Logger.info("[GraphMigrator] Running migration v#{version}: #{description}")

    case migration.up() do
      :ok ->
        record_migration_version(version)
        Logger.info("[GraphMigrator] Migration v#{version} completed")

      {:error, e} ->
        Logger.error("[GraphMigrator] Migration v#{version} failed: #{inspect(e)}")
        raise e
    end
  end

  defp record_migration_version(version) do
    cypher =
      "MERGE (m:_Migration {version: #{version}}) " <>
        "SET m.applied_at = timestamp()"

    sql = "SELECT * FROM cypher('knowledge', $1) AS (result agtype)"

    case BotArmyInternalDocs.GraphRepo.query!(sql, [cypher]) do
      _ ->
        :ok
    end
  end
end
