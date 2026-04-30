defmodule BotArmyInternalDocs.Stores.DocSourceStore do
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Repo
  alias BotArmyInternalDocs.Schemas.DocSource

  @default_tenant_id "00000000-0000-0000-0000-000000000001"
  @default_para_path "docs/personal_os"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list, do: GenServer.call(__MODULE__, :list)
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def create(attrs), do: GenServer.call(__MODULE__, {:create, attrs})
  def update(id, attrs), do: GenServer.call(__MODULE__, {:update, id, attrs})
  def remove(id), do: GenServer.call(__MODULE__, {:remove, id})
  def get_by_location(location), do: GenServer.call(__MODULE__, {:get_by_location, location})
  def enable(id), do: GenServer.call(__MODULE__, {:enable, id})
  def disable(id), do: GenServer.call(__MODULE__, {:disable, id})
  def bootstrap_sources, do: build_bootstrap_sources()

  @impl true
  def init(_opts) do
    Logger.info("[DocSourceStore] Starting...")
    sources = load_all()
    Logger.info("[DocSourceStore] Loaded #{map_size(sources)} source(s)")

    if map_size(sources) == 0 do
      seed_defaults_direct()
    else
      ensure_bootstrap_sources(sources)
    end

    {:ok, %{sources: load_all()}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, {:ok, Map.values(state.sources)}, state}
  end

  def handle_call({:get, id}, _from, state) do
    {:reply, Map.get(state.sources, id, {:error, :not_found}), state}
  end

  def handle_call({:create, attrs}, _from, state) do
    %DocSource{}
    |> DocSource.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, source} ->
        {:reply, {:ok, source}, %{state | sources: Map.put(state.sources, source.id, source)}}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  def handle_call({:update, id, attrs}, _from, state) do
    case Map.get(state.sources, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      source ->
        source
        |> DocSource.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:reply, {:ok, updated}, %{state | sources: Map.put(state.sources, id, updated)}}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end
    end
  end

  def handle_call({:remove, id}, _from, state) do
    case Map.get(state.sources, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      source ->
        Repo.delete(source)
        {:reply, :ok, %{state | sources: Map.delete(state.sources, id)}}
    end
  end

  def handle_call({:get_by_location, location}, _from, state) do
    result =
      state.sources
      |> Map.values()
      |> Enum.find(&(&1.location == location))

    {:reply, if(result, do: {:ok, result}, else: {:error, :not_found}), state}
  end

  def handle_call({:enable, id}, _from, state) do
    update_enabled(id, true, state)
  end

  def handle_call({:disable, id}, _from, state) do
    update_enabled(id, false, state)
  end

  defp update_enabled(id, enabled, state) do
    case Map.get(state.sources, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      source ->
        source
        |> Ecto.Changeset.change(%{enabled: enabled})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:reply, {:ok, updated}, %{state | sources: Map.put(state.sources, id, updated)}}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end
    end
  end

  defp load_all do
    Repo.all(DocSource)
    |> Enum.reduce(%{}, fn source, acc -> Map.put(acc, source.id, source) end)
  end

  defp seed_defaults_direct do
    default_sources = build_bootstrap_sources()

    Enum.each(default_sources, fn attrs ->
      tenant_id = Map.get(attrs, "tenant_id", @default_tenant_id)
      attrs = Map.merge(attrs, %{"tenant_id" => tenant_id})

      case %DocSource{} |> DocSource.changeset(attrs) |> Repo.insert() do
        {:ok, source} -> Logger.info("[DocSourceStore] Seeded source: #{source.name}")
        {:error, cs} -> Logger.warning("[DocSourceStore] Failed to seed: #{inspect(cs.errors)}")
      end
    end)
  end

  defp ensure_bootstrap_sources(existing_sources) do
    existing_locations =
      existing_sources
      |> Map.values()
      |> MapSet.new(& &1.location)

    build_bootstrap_sources()
    |> Enum.reject(&(Map.get(&1, "location") in existing_locations))
    |> Enum.each(fn attrs ->
      tenant_id = Map.get(attrs, "tenant_id", @default_tenant_id)
      attrs = Map.merge(attrs, %{"tenant_id" => tenant_id})

      case %DocSource{} |> DocSource.changeset(attrs) |> Repo.insert() do
        {:ok, source} ->
          Logger.info("[DocSourceStore] Added bootstrap source: #{source.name}")

        {:error, cs} ->
          Logger.warning("[DocSourceStore] Failed to add bootstrap source: #{inspect(cs.errors)}")
      end
    end)
  end

  defp build_bootstrap_sources do
    configured =
      Application.get_env(:bot_army_internal_docs, :default_sources, [])
      |> Enum.map(&normalize_source/1)
      |> Enum.reject(&is_nil/1)

    para =
      para_source()
      |> List.wrap()

    (configured ++ para)
    |> Enum.uniq_by(&Map.get(&1, "location"))
  end

  defp normalize_source(attrs) when is_map(attrs), do: attrs
  defp normalize_source(_), do: nil

  defp para_source do
    path = Application.get_env(:bot_army_internal_docs, :para_docs_path, @default_para_path)
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      %{
        "source_type" => "local_file",
        "location" => expanded,
        "name" => "personal_os_docs",
        "category" => "personal_os",
        "tags" => ["para", "personal_os", "fractional"]
      }
    else
      nil
    end
  end
end
