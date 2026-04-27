defmodule BotArmyInternalDocs.Repo.Migrations.CreateDocChunks do
  use Ecto.Migration

  # nomic-embed-text dimension
  @embedding_dims 768

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    create table(:doc_chunks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:source_id, references(:doc_sources, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:content, :text, null: false)
      add(:content_hash, :varchar, size: 64, null: false)
      add(:chunk_index, :integer, null: false)
      add(:heading, :varchar, size: 500)
      add(:embedding_vector, :vector, size: @embedding_dims)
      add(:embedded_at, :utc_datetime_usec)
      add(:enrichment_status, :string, default: "pending", null: false)
      add(:topics, {:array, :string}, default: [])
      add(:summary, :text)
      add(:metadata, :map, default: %{})
      add(:tenant_id, :binary_id, null: false)
      add(:user_id, :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:doc_chunks, [:source_id, :content_hash],
        name: :doc_chunks_source_id_content_hash_index
      )
    )

    create(index(:doc_chunks, [:source_id]))
    create(index(:doc_chunks, [:tenant_id]))
    create(index(:doc_chunks, [:enrichment_status]))

    # HNSW index for fast ANN search on embeddings
    create(
      index(:doc_chunks, ["embedding_vector vector_cosine_ops"],
        using: :hnsw,
        name: :doc_chunks_embedding_hnsw,
        options: "m = 16, ef_construction = 64"
      )
    )
  end
end
