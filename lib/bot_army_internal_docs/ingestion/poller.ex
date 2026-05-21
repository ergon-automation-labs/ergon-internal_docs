defmodule BotArmyInternalDocs.Ingestion.Poller do
  @moduledoc "Polls local file paths for new or changed documentation sources."
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Ingestion.Chunker
  alias BotArmyInternalDocs.Ingestion.Fetchers.LocalFile
  alias BotArmyInternalDocs.Stores.DocSourceStore

  @default_interval_ms 3_600_000
  @initial_delay_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_fetch do
    GenServer.cast(__MODULE__, :fetch)
  end

  def run_fetch(source_id) do
    GenServer.cast(__MODULE__, {:fetch_source, source_id})
  end

  @impl true
  def init(_opts) do
    Logger.info("[Poller] Starting, initial fetch in #{@initial_delay_ms}ms")
    Process.send_after(self(), :initial_fetch, @initial_delay_ms)
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:initial_fetch, state) do
    poll_all()
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    poll_all()
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:fetch, state) do
    poll_all()
    {:noreply, state}
  end

  def handle_cast({:fetch_source, source_id}, state) do
    case DocSourceStore.get(source_id) do
      {:ok, source} -> poll_source(source)
      {:error, :not_found} -> Logger.warning("[Poller] Source not found: #{source_id}")
    end

    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @default_interval_ms)
  end

  defp poll_all do
    case DocSourceStore.list() do
      {:ok, sources} ->
        Logger.info("[Poller] Polling #{length(sources)} source(s)")
        Enum.each(sources, &poll_source/1)

      {:error, reason} ->
        Logger.error("[Poller] Failed to list sources: #{inspect(reason)}")
    end
  end

  defp poll_source(%{enabled: false} = source) do
    Logger.debug("[Poller] Skipping disabled source: #{source.name}")
  end

  defp poll_source(source) do
    Logger.info("[Poller] Fetching source: #{source.name} (#{source.source_type})")

    case fetch(source) do
      {:ok, documents} ->
        chunk_count =
          documents
          |> Enum.flat_map(fn doc ->
            Chunker.chunk_document(doc, source.id)
          end)
          |> Enum.count()

        DocSourceStore.update(source.id, %{
          "last_fetched" => DateTime.utc_now(),
          "error_count" => 0
        })

        Logger.info(
          "[Poller] Source #{source.name}: #{length(documents)} doc(s), #{chunk_count} chunk(s)"
        )

      {:error, reason} ->
        Logger.warning("[Poller] Fetch failed for #{source.name}: #{inspect(reason)}")

        DocSourceStore.update(source.id, %{
          "error_count" => source.error_count + 1
        })
    end
  end

  defp fetch(%{source_type: "local_file"} = source) do
    LocalFile.fetch(source.location)
  end

  defp fetch(%{source_type: type} = _source) do
    {:error, {:unsupported_type, type}}
  end
end
