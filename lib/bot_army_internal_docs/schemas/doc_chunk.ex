defmodule BotArmyInternalDocs.Schemas.DocChunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "doc_chunks" do
    field(:content, :string)
    field(:content_hash, :string)
    field(:chunk_index, :integer)
    field(:heading, :string)
    field(:embedding_vector, Pgvector.Ecto.Vector)
    field(:embedding_vector_768, Pgvector.Ecto.Vector)
    field(:embedded_at, :utc_datetime_usec)
    field(:enrichment_status, :string, default: "pending")
    field(:topics, {:array, :string}, default: [])
    field(:summary, :string)
    field(:metadata, :map, default: %{})
    field(:tenant_id, :binary_id)
    field(:user_id, :binary_id)

    belongs_to(:source, BotArmyInternalDocs.Schemas.DocSource)

    timestamps(type: :utc_datetime_usec)
  end

  @required [:source_id, :content, :content_hash, :chunk_index, :tenant_id]
  @optional [
    :heading,
    :embedding_vector,
    :embedding_vector_768,
    :embedded_at,
    :enrichment_status,
    :topics,
    :summary,
    :metadata,
    :user_id
  ]

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:content_hash, name: :doc_chunks_source_id_content_hash_index)
    |> foreign_key_constraint(:source_id)
  end
end
