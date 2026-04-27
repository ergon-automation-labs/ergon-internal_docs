defmodule BotArmyInternalDocs.NATS.Consumer do
  use GenServer
  require Logger

  alias BotArmyInternalDocs.Stores.{DocSourceStore, DocChunkStore}
  alias BotArmyRuntime.NATS.Connection

  @version Mix.Project.config()[:version]

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
    %{subject: "internal_docs.search", type: :request_reply, description: "Keyword search"}
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

        {:ok, %{conn: conn, subscriptions: subscriptions, tenant_id: tenant_id}}

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

  defp route_message("internal_docs.ingest", _payload, reply_to, _state) do
    # Phase 2: trigger Poller
    Logger.info("[NATS.Consumer] Ingestion triggered (Phase 2 stub)")
    send_reply(reply_to, %{"ok" => true, "message" => "Ingestion scheduled"})
  end

  defp route_message("events.llm.embedding.created", payload, _reply_to, _state) do
    chunk_id = Map.get(payload, "chunk_id") || Map.get(payload, "reference_id")
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

  defp route_message("internal_docs.query", %{"query" => query_text}, reply_to, _state) do
    # Phase 4: semantic search via embed → vector similarity → graph traversal
    Logger.info(
      "[NATS.Consumer] Query received (Phase 4 stub): #{String.slice(query_text, 0, 50)}"
    )

    send_reply(reply_to, %{
      "ok" => true,
      "results" => [],
      "message" => "Semantic search not yet implemented"
    })
  end

  defp route_message("internal_docs.search", %{"query" => query_text}, reply_to, _state) do
    # Phase 4: keyword search via ILIKE
    Logger.info(
      "[NATS.Consumer] Search received (Phase 4 stub): #{String.slice(query_text, 0, 50)}"
    )

    send_reply(reply_to, %{
      "ok" => true,
      "results" => [],
      "message" => "Keyword search not yet implemented"
    })
  end

  defp route_message(topic, _payload, _reply_to, _state) do
    Logger.debug("[NATS.Consumer] Unhandled topic: #{topic}")
    :ok
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
      {:error, reason} -> Logger.warning("[NATS.Consumer] Reply failed: #{inspect(reason)}")
    end
  end
end
