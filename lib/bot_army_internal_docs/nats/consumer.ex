defmodule BotArmyInternalDocs.NATS.Consumer do
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Stores.{DocSourceStore, DocChunkStore}
  alias BotArmyRuntime.NATS.Connection

  @registry_heartbeat_ms 20_000
  @version Mix.Project.config()[:version]

  # Hard caps for internal_docs.chunk.get response size (characters)
  @chunk_get_max_hard 500_000
  @chunk_get_default 200_000

  @subjects [
    %{
      subject: "internal_docs.source.list",
      type: :request_reply,
      description: "List doc sources"
    },
    %{subject: "internal_docs.source.add", type: :request_reply, description: "Add doc source"},
    %{
      subject: "internal_docs.source.remove",
      type: :request_reply,
      description: "Remove doc source"
    },
    %{
      subject: "internal_docs.source.update",
      type: :request_reply,
      description: "Update doc source"
    },
    %{subject: "internal_docs.ingest", type: :subscribe, description: "Trigger ingestion"},
    %{
      subject: "events.llm.embedding.created",
      type: :subscribe,
      description: "Embedding callback"
    },
    %{subject: "internal_docs.query", type: :request_reply, description: "Semantic search"},
    %{subject: "internal_docs.search", type: :request_reply, description: "Keyword search"},
    %{
      subject: "internal_docs.chunk.get",
      type: :request_reply,
      description: "Fetch full chunk text + optional neighboring chunks by index"
    }
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def embedding_chunk_id(payload) when is_map(payload) do
    Map.get(payload, "chunk_id") || Map.get(payload, "reference_id") ||
      Map.get(payload, "card_id")
  end

  @impl true
  def init(opts) do
    tenant_id = Keyword.get(opts, :tenant_id)

    case GenServer.call(Connection, :get_connection, 5000) do
      {:ok, conn} ->
        subscriptions =
          for %{subject: subject} <- @subjects do
            {Gnat.sub(conn, self(), subject), subject}
          end

        Logger.info("[NATS.Consumer] Subscribed to internal_docs subjects")
        BotArmyRuntime.Registry.register("internal_docs", @subjects, @version)
        Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)

        {:ok,
         %{
           conn: conn,
           subscriptions: subscriptions,
           tenant_id: tenant_id,
           registry_registered?: true
         }}

      {:error, reason} ->
        Logger.error("[NATS.Consumer] NATS connection failed: #{inspect(reason)}")
        {:stop, :nats_connection_failed}
    end
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      case decode_message(msg.body) do
        {:ok, payload} ->
          route_message(msg.topic, payload, msg.reply_to, state)

        {:error, reason} ->
          Logger.warning("[NATS.Consumer] Decode failed: #{inspect(reason)}")

          if msg.reply_to,
            do: send_reply(msg.reply_to, %{"ok" => false, "error" => "decode_failed"})
      end
    end)

    {:noreply, state}
  end

  def handle_info(:registry_heartbeat, state) do
    if Map.get(state, :registry_registered?) do
      BotArmyRuntime.Registry.register("internal_docs", @subjects, @version)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp route_message("internal_docs.source.list", _payload, reply_to, _state) do
    {:ok, sources} = DocSourceStore.list()

    reply = %{
      "ok" => true,
      "sources" => Enum.map(sources, &source_to_map/1)
    }

    send_reply(reply_to, reply)
  end

  defp route_message("internal_docs.source.add", payload, reply_to, _state) do
    case DocSourceStore.create(payload) do
      {:ok, source} ->
        BotArmyInternalDocs.NATS.Publisher.publish_source_added(source)
        send_reply(reply_to, %{"ok" => true, "source" => source_to_map(source)})

      {:error, changeset} ->
        send_reply(reply_to, %{"ok" => false, "error" => format_errors(changeset)})
    end
  end

  defp route_message("internal_docs.source.remove", %{"source_id" => id}, reply_to, _state) do
    case DocSourceStore.remove(id) do
      :ok ->
        send_reply(reply_to, %{"ok" => true})

      {:error, :not_found} ->
        send_reply(reply_to, %{"ok" => false, "error" => "not found"})
    end
  end

  defp route_message(
         "internal_docs.source.update",
         %{"source_id" => id} = payload,
         reply_to,
         _state
       ) do
    attrs = Map.drop(payload, ["source_id"])

    case DocSourceStore.update(id, attrs) do
      {:ok, source} ->
        send_reply(reply_to, %{"ok" => true, "source" => source_to_map(source)})

      {:error, reason} ->
        send_reply(reply_to, %{"ok" => false, "error" => inspect(reason)})
    end
  end

  defp route_message("internal_docs.ingest", payload, reply_to, _state) do
    source_id = Map.get(payload, "source_id")

    if source_id do
      Logger.info("[NATS.Consumer] Ingestion triggered for source #{source_id}")
      BotArmyInternalDocs.Ingestion.Poller.run_fetch(source_id)
    else
      Logger.info("[NATS.Consumer] Full ingestion triggered")
      BotArmyInternalDocs.Ingestion.Poller.run_fetch()
    end

    send_reply(reply_to, %{"ok" => true, "message" => "Ingestion started"})
  end

  defp route_message("events.llm.embedding.created", payload, _reply_to, _state) do
    chunk_id = embedding_chunk_id(payload)
    vector = Map.get(payload, "embedding")

    if chunk_id && vector do
      case DocChunkStore.update_embedding(chunk_id, vector) do
        {:ok, _} ->
          Logger.debug("[NATS.Consumer] Embedding stored for chunk #{chunk_id}")

        {:error, reason} ->
          Logger.warning("[NATS.Consumer] Embedding store failed: #{inspect(reason)}")
      end
    end
  end

  defp route_message("internal_docs.query", %{"query" => query_text} = payload, reply_to, _state) do
    Logger.info("[NATS.Consumer] Semantic query: #{String.slice(query_text, 0, 50)}")
    limit = Map.get(payload, "limit", 5)

    Task.start(fn ->
      case BotArmyInternalDocs.Ingestion.Embedder.embed(query_text) do
        {:ok, vector} ->
          case DocChunkStore.search_by_vector(vector, limit) do
            {:ok, chunks} ->
              results = Enum.map(chunks, &chunk_to_result/1)

              send_reply(reply_to, %{
                "ok" => true,
                "results" => results,
                "count" => length(results)
              })

            {:error, reason} ->
              send_reply(reply_to, %{"ok" => false, "error" => inspect(reason)})
          end

        {:error, reason} ->
          Logger.warning("[NATS.Consumer] Query embedding failed: #{inspect(reason)}")

          case DocChunkStore.search_by_keyword(query_text, limit) do
            {:ok, chunks} ->
              results = Enum.map(chunks, &chunk_to_result/1)

              send_reply(reply_to, %{
                "ok" => true,
                "results" => results,
                "count" => length(results),
                "fallback" => "keyword"
              })

            {:error, reason2} ->
              send_reply(reply_to, %{"ok" => false, "error" => inspect({reason, reason2})})
          end
      end
    end)

    :ok
  end

  defp route_message("internal_docs.chunk.get", payload, reply_to, _state)
       when is_map(payload) do
    chunk_id = Map.get(payload, "chunk_id")

    if is_nil(chunk_id) or chunk_id == "" do
      send_reply(reply_to, %{"ok" => false, "error" => "chunk_id required"})
    else
      max_chars = clamp_max_chars(Map.get(payload, "max_chars"))
      before_n = clamp_neighbor(Map.get(payload, "before", 0))
      after_n = clamp_neighbor(Map.get(payload, "after", 0))

      case DocChunkStore.get(chunk_id) do
        {:ok, chunk} ->
          content =
            chunk.content
            |> slice_chars(max_chars)

          neighbors =
            if before_n > 0 or after_n > 0 do
              case DocChunkStore.neighbors(chunk_id, before_n, after_n) do
                {:ok, rows} -> Enum.map(rows, &chunk_to_neighbor/1)
                _ -> []
              end
            else
              []
            end

          send_reply(reply_to, %{
            "ok" => true,
            "chunk" => %{
              "id" => chunk.id,
              "source_id" => chunk.source_id,
              "heading" => chunk.heading,
              "content" => content,
              "content_truncated" => String.length(chunk.content) > max_chars,
              "max_chars" => max_chars,
              "chunk_index" => chunk.chunk_index,
              "enrichment_status" => chunk.enrichment_status,
              "topics" => chunk.topics,
              "summary" => chunk.summary
            },
            "neighbors" => neighbors
          })

        {:error, :not_found} ->
          send_reply(reply_to, %{"ok" => false, "error" => "not_found"})
      end
    end
  end

  defp route_message("internal_docs.search", %{"query" => query_text} = payload, reply_to, _state) do
    Logger.info("[NATS.Consumer] Keyword search: #{String.slice(query_text, 0, 50)}")

    limit = Map.get(payload, "limit", 10)

    case DocChunkStore.search_by_keyword(query_text, limit) do
      {:ok, chunks} ->
        results = Enum.map(chunks, &chunk_to_result/1)
        send_reply(reply_to, %{"ok" => true, "results" => results, "count" => length(results)})

      {:error, reason} ->
        send_reply(reply_to, %{"ok" => false, "error" => inspect(reason)})
    end
  end

  defp route_message(topic, _payload, _reply_to, _state) do
    Logger.debug("[NATS.Consumer] Unhandled topic: #{topic}")
    :ok
  end

  defp chunk_to_result(chunk) do
    %{
      "id" => chunk.id,
      "source_id" => chunk.source_id,
      "heading" => chunk.heading,
      "content" => String.slice(chunk.content, 0, 500),
      "snippet_chars" => min(String.length(chunk.content), 500),
      "chunk_index" => chunk.chunk_index,
      "enrichment_status" => chunk.enrichment_status,
      "topics" => chunk.topics,
      "summary" => chunk.summary
    }
  end

  defp chunk_to_neighbor(chunk) do
    %{
      "id" => chunk.id,
      "chunk_index" => chunk.chunk_index,
      "heading" => chunk.heading,
      "content" => String.slice(chunk.content, 0, 1200),
      "snippet_chars" => min(String.length(chunk.content), 1200)
    }
  end

  defp clamp_max_chars(nil), do: @chunk_get_default

  defp clamp_max_chars(n) when is_integer(n) and n > 0 do
    min(n, @chunk_get_max_hard)
  end

  defp clamp_max_chars(_), do: @chunk_get_default

  defp clamp_neighbor(n) when is_integer(n) and n >= 0, do: min(n, 5)
  defp clamp_neighbor(_), do: 0

  defp slice_chars(nil, _max), do: ""

  defp slice_chars(text, max_chars) when is_binary(text) do
    if String.length(text) <= max_chars, do: text, else: String.slice(text, 0, max_chars)
  end

  defp source_to_map(source) do
    %{
      "id" => source.id,
      "source_type" => source.source_type,
      "location" => source.location,
      "name" => source.name,
      "category" => source.category,
      "tags" => source.tags,
      "enabled" => source.enabled,
      "last_fetched" => source.last_fetched,
      "error_count" => source.error_count,
      "fetch_interval_ms" => source.fetch_interval_ms
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp decode_message(body) do
    case BotArmyCore.NATS.Decoder.decode(body) do
      {:ok, %{"payload" => payload}} ->
        {:ok, payload}

      {:ok, payload} when is_map(payload) ->
        {:ok, payload}

      {:error, _reason} ->
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          error -> error
        end
    end
  end

  defp send_reply(nil, _payload), do: :ok

  defp send_reply(reply_to, payload) when is_binary(reply_to) do
    case BotArmyRuntime.NATS.Publisher.publish(reply_to, payload) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("[NATS.Consumer] Reply failed: #{inspect(reason)}")
    end
  end
end
