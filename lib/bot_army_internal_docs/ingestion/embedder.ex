defmodule BotArmyInternalDocs.Ingestion.Embedder do
  @moduledoc false
  require Logger

  @default_model "nomic-embed-text"
  @embed_timeout_ms 30_000

  def embed(text, model \\ nil) do
    model = model || @default_model
    reference_id = UUID.uuid4()

    event = %{
      "event_id" => reference_id,
      "event" => "llm.embed.request",
      "schema_version" => "1.0",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "internal_docs.embedder",
      "payload" => %{
        "text" => text,
        "model" => model,
        "reference_id" => reference_id
      }
    }

    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5000) do
      {:ok, conn} ->
        {:ok, _sid} = Gnat.sub(conn, self(), "events.llm.embedding.created")
        {:ok, _sid} = Gnat.sub(conn, self(), "events.llm.error")

        case BotArmyRuntime.NATS.Publisher.publish("llm.embed.request", event) do
          {:ok, _} ->
            wait_for_embedding(conn, reference_id, @embed_timeout_ms)

          {:error, reason} ->
            cleanup_subscriptions(conn)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_embedding(conn, reference_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for_embedding(conn, reference_id, deadline)
  end

  defp do_wait_for_embedding(conn, reference_id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      cleanup_subscriptions(conn)
      Logger.warning("[Embedder] Embed request timed out")
      {:error, :timeout}
    else
      receive do
        {:msg, %{topic: "events.llm.embedding.created", body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"payload" => %{"embedding" => vector}} = event} when is_list(vector) ->
              if event_reference_id(event) == reference_id do
                cleanup_subscriptions(conn)
                {:ok, vector}
              else
                do_wait_for_embedding(conn, reference_id, deadline)
              end

            {:ok, _other_event} ->
              do_wait_for_embedding(conn, reference_id, deadline)

            {:error, reason} ->
              cleanup_subscriptions(conn)
              {:error, {:json_decode, reason}}
          end

        {:msg, %{topic: "events.llm.error", body: body}} ->
          case Jason.decode(body) do
            {:ok, event} ->
              if event_reference_id(event) == reference_id do
                cleanup_subscriptions(conn)
                Logger.warning("[Embedder] Embed request failed: #{inspect(event["payload"])}")
                {:error, {:llm_error, Map.get(event, "payload")}}
              else
                do_wait_for_embedding(conn, reference_id, deadline)
              end

            {:error, reason} ->
              cleanup_subscriptions(conn)
              {:error, {:json_decode, reason}}
          end
      after
        remaining ->
          cleanup_subscriptions(conn)
          Logger.warning("[Embedder] Embed request timed out")
          {:error, :timeout}
      end
    end
  end

  defp event_reference_id(event) when is_map(event) do
    Map.get(event, "triggered_by_event_id") ||
      get_in(event, ["payload", "triggered_by_event_id"]) ||
      get_in(event, ["payload", "reference_id"])
  end

  defp cleanup_subscriptions(conn) do
    Gnat.unsub(conn, self(), "events.llm.embedding.created")
    Gnat.unsub(conn, self(), "events.llm.error")
    :ok
  end
end
