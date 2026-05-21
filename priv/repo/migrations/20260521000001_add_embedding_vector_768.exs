defmodule BotArmyInternalDocs.Repo.Migrations.AddEmbeddingVector768 do
  use Ecto.Migration

  def up do
    alter table(:doc_chunks) do
      add(:embedding_vector_768, :vector, size: 768, null: true)
    end

    # Create index for 768-dimensional embeddings
    create(
      index(:doc_chunks, ["embedding_vector_768 vector_cosine_ops"],
        using: :hnsw,
        name: :doc_chunks_embedding_768_hnsw,
        options: "m = 16, ef_construction = 64"
      )
    )
  end

  def down do
    drop_if_exists(
      index(:doc_chunks, ["embedding_vector_768 vector_cosine_ops"],
        name: :doc_chunks_embedding_768_hnsw
      )
    )

    alter table(:doc_chunks) do
      remove(:embedding_vector_768)
    end
  end
end
