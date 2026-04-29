defmodule BotArmyInternalDocs.Stores.DocChunkStore do
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
  def create(attrs), do: GenServer.call(__MODULE__, {:create, attrs})
  def update(id, attrs), do: GenServer.call(__MODULE__, {:update, id, attrs})

  def upsert_chunk(attrs), do: GenServer.call(__MODULE__, {:upsert_chunk, attrs})

  def update_embedding(id, vector),
    do: GenServer.call(__MODULE__, {:update_embedding, id, vector})

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
        chunk
        |> Ecto.Changeset.change(%{embedding_vector: vector, embedded_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:reply, {:ok, updated}, state}
          {:error, cs} -> {:reply, {:error, cs}, state}
        end
    end
  end

  def handle_call({:search_by_vector, vector, limit}, _from, state) do
    results =
      from(c in DocChunk,
        order_by: fragment("embedding_vector <=> ?", ^vector),
        limit: ^limit,
        where: not is_nil(c.embedding_vector)
      )
      |> Repo.all()

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
        where: c.enrichment_status == "pending" and is_nil(c.embedding_vector),
        limit: 20
      )
      |> Repo.all()

    {:reply, {:ok, chunks}, state}
  end

  def handle_call({:search_by_keyword, query_text, limit}, _from, state) do
    words = query_text |> String.split(~r/\s+/, trim: true) |> Enum.take(5)

    results =
      if words == [] do
        []
      else
        from(c in DocChunk,
          where:
            fragment(
              "((?) @@ websearch_to_tsquery('english', ?))",
              c.content,
              ^query_text
            ) or
              ilike(c.content, ^"%#{hd(words)}%") or
              ilike(c.heading, ^"%#{hd(words)}%"),
          limit: ^limit,
          order_by:
            fragment("CASE WHEN ilike(?, ?) THEN 0 ELSE 1 END", c.heading, ^"%#{hd(words)}%")
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
end
