defmodule BotArmyInternalDocs.Schemas.DocSource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "doc_sources" do
    field(:source_type, :string)
    field(:location, :string)
    field(:name, :string)
    field(:category, :string)
    field(:tags, {:array, :string}, default: [])
    field(:enabled, :boolean, default: true)
    field(:last_fetched, :utc_datetime_usec)
    field(:error_count, :integer, default: 0)
    field(:fetch_interval_ms, :integer, default: 3_600_000)
    field(:metadata, :map, default: %{})
    field(:tenant_id, :binary_id)
    field(:user_id, :binary_id)

    has_many(:chunks, BotArmyInternalDocs.Schemas.DocChunk,
      foreign_key: :source_id,
      on_delete: :delete_all
    )

    timestamps(type: :utc_datetime_usec)
  end

  @required [:source_type, :location, :name, :tenant_id]
  @optional [
    :category,
    :tags,
    :enabled,
    :last_fetched,
    :error_count,
    :fetch_interval_ms,
    :metadata,
    :user_id
  ]

  def changeset(source, attrs) do
    source
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source_type, ~w(local_file github_wiki web_url))
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:category, min: 1, max: 50)
    |> unique_constraint(:location)
  end
end
