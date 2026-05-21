defmodule BotArmyInternalDocs.Ingestion.EmbedWorker do
  @moduledoc "Background GenServer that generates embeddings for doc chunks in batches."
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Stores.DocChunkStore
  alias BotArmyInternalDocs.NATS.Publisher

  @poll_interval_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def queue_chunk(chunk_id) do
    GenServer.cast(__MODULE__, {:queue_chunk, chunk_id})
  end

  def queue_chunks(chunk_ids) when is_list(chunk_ids) do
    GenServer.cast(__MODULE__, {:queue_chunks, chunk_ids})
  end

  @impl true
  def init(_opts) do
    Logger.info("[EmbedWorker] Starting, polling every #{@poll_interval_ms}ms")
    schedule_poll()
    {:ok, %{queue: :queue.new(), processing: false}}
  end

  @impl true
  def handle_cast({:queue_chunk, chunk_id}, state) do
    new_queue = :queue.in(chunk_id, state.queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_cast({:queue_chunks, chunk_ids}, state) do
    new_queue =
      Enum.reduce(chunk_ids, state.queue, fn id, q -> :queue.in(id, q) end)

    {:noreply, %{state | queue: new_queue}}
  end

  @impl true
  def handle_info(:poll_pending, state) do
    schedule_poll()
    new_state = process_pending_chunks(state)
    {:noreply, new_state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_pending, @poll_interval_ms)
  end

  defp process_pending_chunks(state) do
    pending = DocChunkStore.list_pending_embeddings()

    case pending do
      {:ok, chunks} when chunks != [] ->
        Logger.info("[EmbedWorker] Found #{length(chunks)} chunk(s) pending embedding")

        Enum.each(chunks, fn chunk ->
          request_embedding(chunk)
        end)

        state

      {:ok, []} ->
        state

      {:error, reason} ->
        Logger.warning("[EmbedWorker] Failed to query pending chunks: #{inspect(reason)}")
        state
    end
  end

  defp request_embedding(chunk) do
    Publisher.request_embedding(chunk.id, chunk.content)
    Logger.debug("[EmbedWorker] Requested embedding for chunk #{chunk.id}")
  end
end
