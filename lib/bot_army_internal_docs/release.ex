defmodule BotArmyInternalDocs.Release do
  @moduledoc false

  alias BotArmyLibraryRuntime.Ecto.MigrationRunner

  @app :bot_army_internal_docs

  def migrate do
    MigrationRunner.run(
      repo_module: BotArmyInternalDocs.Repo,
      app_module: @app
    )
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create do
    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, term} -> {:error, term}
      end
    end
  end

  def migrate_graph do
    BotArmyInternalDocs.GraphMigrator.run()
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
end
