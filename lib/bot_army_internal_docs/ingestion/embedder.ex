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
        :ok = Gnat.sub(conn, self(), "events.llm.embedding.created")

        case BotArmyRuntime.NATS.Publisher.publish("llm.embed.request", event) do
          {:ok, _} ->
            wait_for_embedding(conn, reference_id, @embed_timeout_ms)

          {:error, reason} ->
            Gnat.unsub(conn, self(), "events.llm.embedding.created")
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
      Gnat.unsub(conn, self(), "events.llm.embedding.created")
      Logger.warning("[Embedder] Embed request timed out")
      {:error, :timeout}
    else
      receive do
        {:msg, %{topic: "events.llm.embedding.created", body: body}} ->
          case Jason.decode(body) do
            {:ok,
             %{
               "payload" => %{"embedding" => vector},
               "triggered_by_event_id" => ^reference_id
             }} ->
              Gnat.unsub(conn, self(), "events.llm.embedding.created")
              {:ok, vector}

            {:ok, _other_event} ->
              do_wait_for_embedding(conn, reference_id, deadline)

            {:error, reason} ->
              Gnat.unsub(conn, self(), "events.llm.embedding.created")
              {:error, {:json_decode, reason}}
          end
      after
        remaining ->
          Gnat.unsub(conn, self(), "events.llm.embedding.created")
          Logger.warning("[Embedder] Embed request timed out")
          {:error, :timeout}
      end
    end
  end
end
