defmodule BotArmyInternalDocs.Repo.Migrations.ResizeDocChunkEmbeddingVectorTo4096 do
  use Ecto.Migration

  @new_embedding_dims 4096
  @old_embedding_dims 768

  def up do
    drop_if_exists(
      index(:doc_chunks, ["embedding_vector vector_cosine_ops"], name: :doc_chunks_embedding_hnsw)
    )

    execute(
      "ALTER TABLE doc_chunks ALTER COLUMN embedding_vector TYPE vector(#{@new_embedding_dims})"
    )
  end

  def down do
    drop_if_exists(
      index(:doc_chunks, ["embedding_vector vector_cosine_ops"], name: :doc_chunks_embedding_hnsw)
    )

    execute(
      "ALTER TABLE doc_chunks ALTER COLUMN embedding_vector TYPE vector(#{@old_embedding_dims})"
    )

    create(
      index(:doc_chunks, ["embedding_vector vector_cosine_ops"],
        using: :hnsw,
        name: :doc_chunks_embedding_hnsw,
        options: "m = 16, ef_construction = 64"
      )
    )
  end
end
