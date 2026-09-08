defmodule BotArmyInternalDocs.Ingestion.FileWatcher do
  @moduledoc "Watches source directories and debounces file changes for re-ingestion."
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Ingestion.Poller
  alias BotArmyInternalDocs.Stores.DocSourceStore

  @debounce_ms 10 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    watched = watched_dirs()

    case FileSystem.start_link(dirs: watched, latency: 1000) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        Logger.info("[FileWatcher] Watching #{length(watched)} directories")
        {:ok, %{fs_pid: pid, pending_sources: %{}, timers: %{}, watched_dirs: watched}}

      {:error, reason} ->
        Logger.warning("[FileWatcher] Failed to start file system monitor: #{inspect(reason)}")
        {:ok, %{fs_pid: nil, pending_sources: %{}, timers: %{}, watched_dirs: watched}}

      # :ignore — the file_system backend couldn't launch its port program
      # (alpine runtime images ship no inotify binary; caught in starter
      # container builds 2026-09-08). Run without live watching; the Poller
      # still fetches on its own schedule.
      :ignore ->
        Logger.warning("[FileWatcher] File system backend unavailable (:ignore) — continuing without live watching")
        {:ok, %{fs_pid: nil, pending_sources: %{}, timers: %{}, watched_dirs: watched}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    source_id = find_source_for_path(path)

    if source_id do
      new_state = debounce_source(source_id, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info({:trigger_ingest, source_id}, state) do
    Logger.info("[FileWatcher] Triggering ingest for source #{source_id} after debounce")
    Poller.run_fetch(source_id)

    new_timers = Map.delete(state.timers, source_id)
    {:noreply, %{state | timers: new_timers}}
  end

  defp debounce_source(source_id, state) do
    case Map.get(state.timers, source_id) do
      nil ->
        timer = Process.send_after(self(), {:trigger_ingest, source_id}, @debounce_ms)
        Logger.debug("[FileWatcher] Debouncing changes for source #{source_id}")
        %{state | timers: Map.put(state.timers, source_id, timer)}

      existing_timer ->
        Process.cancel_timer(existing_timer)
        timer = Process.send_after(self(), {:trigger_ingest, source_id}, @debounce_ms)
        Logger.debug("[FileWatcher] Resetting debounce timer for source #{source_id}")
        %{state | timers: Map.put(state.timers, source_id, timer)}
    end
  end

  defp watched_dirs do
    db_dirs =
      case DocSourceStore.list() do
        {:ok, sources} ->
          sources
          |> Enum.filter(fn s -> s.enabled && s.source_type == "local_file" end)
          |> Enum.map(& &1.location)

        {:error, _reason} ->
          []
      end

    env_dirs = env_watch_paths()
    (db_dirs ++ env_dirs) |> Enum.uniq()
  end

  defp env_watch_paths do
    case System.get_env("INTERNAL_DOCS_WATCH_PATHS") do
      nil ->
        []

      raw ->
        raw
        |> String.split(":")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&Path.expand/1)
    end
  end

  defp find_source_for_path(path) do
    case DocSourceStore.list() do
      {:ok, sources} ->
        sources
        |> Enum.find(fn source ->
          source.enabled && String.starts_with?(path, source.location)
        end)
        |> then(&if(&1, do: &1.id, else: nil))

      {:error, _reason} ->
        nil
    end
  end
end
