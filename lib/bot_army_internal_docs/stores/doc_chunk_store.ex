defmodule BotArmyInternalDocs.Stores.DocChunkStore do
  @moduledoc "In-memory + Ecto store for chunked documentation text segments."
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Repo
  alias BotArmyInternalDocs.Schemas.DocChunk
  import Ecto.Query

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list(source_id \\ nil), do: GenServer.call(__MODULE__, {:list, source_id})
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def get_many(ids), do: GenServer.call(__MODULE__, {:get_many, ids})
  def create(attrs), do: GenServer.call(__MODULE__, {:create, attrs})
  def update(id, attrs), do: GenServer.call(__MODULE__, {:update, id, attrs})

  def upsert_chunk(attrs), do: GenServer.call(__MODULE__, {:upsert_chunk, attrs})

  def update_embedding(id, vector),
    do: GenServer.call(__MODULE__, {:update_embedding, id, vector})

  def mark_embedded(id),
    do: GenServer.call(__MODULE__, {:mark_embedded, id})

  def search_by_vector(vector, limit \\ 5),
    do: GenServer.call(__MODULE__, {:search_by_vector, vector, limit})

  def mark_enriched(id, summary, topics),
    do: GenServer.call(__MODULE__, {:mark_enriched, id, summary, topics})

  def search_by_keyword(query_text, limit \\ 10),
    do: GenServer.call(__MODULE__, {:search_by_keyword, query_text, limit})

  @doc """
  Load chunks in `[chunk_index - before, chunk_index + after]` for the same source as `chunk_id`.
  """
  def neighbors(chunk_id, before_n \\ 0, after_n \\ 0),
    do: GenServer.call(__MODULE__, {:neighbors, chunk_id, before_n, after_n})

  def list_pending_embeddings,
    do: GenServer.call(__MODULE__, :list_pending_embeddings)

  @impl true
  def init(_opts) do
    Logger.info("[DocChunkStore] Starting...")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:list, nil}, _from, state) do
    chunks = Repo.all(DocChunk)
    {:reply, {:ok, chunks}, state}
  end

  def handle_call({:list, source_id}, _from, state) do
    chunks =
      from(c in DocChunk,
        where: c.source_id == ^source_id,
        order_by: [asc: c.chunk_index]
      )
      |> Repo.all()

    {:reply, {:ok, chunks}, state}
  end

  def handle_call({:get, id}, _from, state) do
    result = Repo.get(DocChunk, id)
    {:reply, if(result, do: {:ok, result}, else: {:error, :not_found}), state}
  end

  def handle_call({:get_many, ids}, _from, state) when is_list(ids) do
    chunks = Repo.all(from(c in DocChunk, where: c.id in ^ids))
    {:reply, {:ok, chunks}, state}
  end

  def handle_call({:create, attrs}, _from, state) do
    %DocChunk{}
    |> DocChunk.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, chunk} -> {:reply, {:ok, chunk}, state}
      {:error, changeset} -> {:reply, {:error, changeset}, state}
    end
  end

  def handle_call({:update, id, attrs}, _from, state) do
    case Repo.get(DocChunk, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      chunk ->
        chunk
        |> DocChunk.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:reply, {:ok, updated}, state}
          {:error, changeset} -> {:reply, {:error, changeset}, state}
        end
    end
  end

  def handle_call({:upsert_chunk, attrs}, _from, state) do
    source_id = attrs[:source_id] || attrs["source_id"]
    content_hash = attrs[:content_hash] || attrs["content_hash"]

    existing =
      Repo.get_by(DocChunk, source_id: source_id, content_hash: content_hash)

    if existing do
      existing
      |> Ecto.Changeset.change(%{
        metadata: attrs[:metadata] || attrs["metadata"] || existing.metadata
      })
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:reply, {:ok, updated, :existing}, state}
        {:error, cs} -> {:reply, {:error, cs}, state}
      end
    else
      %DocChunk{}
      |> DocChunk.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, chunk} -> {:reply, {:ok, chunk, :new}, state}
        {:error, cs} -> {:reply, {:error, cs}, state}
      end
    end
  end

  def handle_call({:update_embedding, id, vector}, _from, state) do
    case Repo.get(DocChunk, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      chunk ->
        dim = vector_dimension(vector)
        field = if dim == 768, do: :embedding_vector_768, else: :embedding_vector

        chunk
        |> Ecto.Changeset.change(%{field => vector, embedded_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:reply, {:ok, updated}, state}
          {:error, cs} -> {:reply, {:error, cs}, state}
        end
    end
  end

  def handle_call({:mark_embedded, id}, _from, state) do
    case Repo.get(DocChunk, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      chunk ->
        chunk
        |> Ecto.Changeset.change(%{enrichment_status: "embedded"})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:reply, {:ok, updated}, state}
          {:error, cs} -> {:reply, {:error, cs}, state}
        end
    end
  end

  def handle_call({:search_by_vector, vector, limit}, _from, state) do
    dim = vector_dimension(vector)

    results =
      if dim == 768 do
        from(c in DocChunk,
          order_by: fragment("embedding_vector_768 <=> ?", ^vector),
          limit: ^limit,
          where: not is_nil(c.embedding_vector_768)
        )
        |> Repo.all()
      else
        from(c in DocChunk,
          order_by: fragment("embedding_vector <=> ?", ^vector),
          limit: ^limit,
          where: not is_nil(c.embedding_vector)
        )
        |> Repo.all()
      end

    {:reply, {:ok, results}, state}
  end

  def handle_call({:mark_enriched, id, summary, topics}, _from, state) do
    case Repo.get(DocChunk, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      chunk ->
        chunk
        |> Ecto.Changeset.change(%{
          enrichment_status: "done",
          summary: summary,
          topics: topics
        })
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:reply, {:ok, updated}, state}
          {:error, cs} -> {:reply, {:error, cs}, state}
        end
    end
  end

  def handle_call(:list_pending_embeddings, _from, state) do
    chunks =
      from(c in DocChunk,
        where:
          c.enrichment_status == "pending" and is_nil(c.embedding_vector) and
            is_nil(c.embedding_vector_768),
        limit: 20
      )
      |> Repo.all()

    if chunks == [] do
      Logger.debug(
        "[DocChunkStore] list_pending_embeddings: 0 chunks found. Checking statuses..."
      )

      all_statuses =
        from(c in DocChunk,
          group_by: c.enrichment_status,
          select: {c.enrichment_status, count(c.id)}
        )
        |> Repo.all()
        |> Enum.map_join(", ", fn {status, count} -> "#{status}:#{count}" end)

      Logger.debug("[DocChunkStore] Chunk statuses: #{all_statuses}")

      # Check embedding column status for pending chunks
      pending_counts =
        from(c in DocChunk,
          where: c.enrichment_status == "pending",
          select: {
            count(c.id),
            count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", c.embedding_vector)),
            count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", c.embedding_vector_768)),
            count(
              fragment(
                "CASE WHEN ? IS NULL AND ? IS NULL THEN 1 END",
                c.embedding_vector,
                c.embedding_vector_768
              )
            )
          }
        )
        |> Repo.one()

      Logger.debug(
        "[DocChunkStore] Pending chunks - total:#{elem(pending_counts, 0)}, has_4096:#{elem(pending_counts, 1)}, has_768:#{elem(pending_counts, 2)}, both_null:#{elem(pending_counts, 3)}"
      )
    end

    {:reply, {:ok, chunks}, state}
  end

  def handle_call({:search_by_keyword, query_text, limit}, _from, state) do
    words = query_text |> String.split(~r/\s+/, trim: true) |> Enum.take(5)
    first_word_like = if words == [], do: nil, else: "%#{hd(words)}%"

    results =
      if words == [] do
        []
      else
        from(c in DocChunk,
          where:
            fragment(
              "(to_tsvector('english', coalesce(?, '')) @@ websearch_to_tsquery('english', ?))",
              c.content,
              ^query_text
            ) or
              ilike(c.content, ^first_word_like) or
              ilike(c.heading, ^first_word_like),
          limit: ^limit,
          order_by:
            fragment(
              "CASE WHEN coalesce(?, '') ILIKE ? THEN 0 ELSE 1 END",
              c.heading,
              ^first_word_like
            )
        )
        |> Repo.all()
      end

    {:reply, {:ok, results}, state}
  end

  def handle_call({:neighbors, chunk_id, before_n, after_n}, _from, state) do
    case Repo.get(DocChunk, chunk_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      anchor ->
        low = anchor.chunk_index - max(0, before_n)
        high = anchor.chunk_index + max(0, after_n)

        rows =
          from(c in DocChunk,
            where: c.source_id == ^anchor.source_id,
            where: c.chunk_index >= ^low and c.chunk_index <= ^high,
            order_by: [asc: c.chunk_index]
          )
          |> Repo.all()

        {:reply, {:ok, rows}, state}
    end
  end

  defp vector_dimension(vector) when is_list(vector) do
    Enum.count(vector)
  end

  defp vector_dimension(vector) when is_map(vector) do
    if Map.has_key?(vector, :data) do
      vector.data |> Enum.count()
    else
      Enum.count(vector)
    end
  end
end
