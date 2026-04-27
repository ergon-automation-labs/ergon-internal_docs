defmodule BotArmyInternalDocs.Repo.Migrations.CreateDocSources do
  use Ecto.Migration

  def change do
    create table(:doc_sources, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:source_type, :string, null: false)
      add(:location, :string, null: false)
      add(:name, :varchar, size: 200, null: false)
      add(:category, :varchar, size: 50)
      add(:tags, {:array, :string}, default: [])
      add(:enabled, :boolean, default: true, null: false)
      add(:last_fetched, :utc_datetime_usec)
      add(:error_count, :integer, default: 0, null: false)
      add(:fetch_interval_ms, :integer, default: 3_600_000, null: false)
      add(:metadata, :map, default: %{})
      add(:tenant_id, :binary_id, null: false)
      add(:user_id, :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:doc_sources, [:location]))
    create(index(:doc_sources, [:tenant_id]))
    create(index(:doc_sources, [:source_type]))
    create(index(:doc_sources, [:enabled]))
  end
end
