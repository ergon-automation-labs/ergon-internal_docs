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

    case BotArmyRuntime.NATS.Connection.get_connection() do
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
    receive do
      {:msg, %{topic: "events.llm.embedding.created", body: body}} ->
        Gnat.unsub(conn, self(), "events.llm.embedding.created")

        case Jason.decode(body) do
          {:ok,
           %{"payload" => %{"embedding" => vector}, "triggered_by_event_id" => ^reference_id}} ->
            {:ok, vector}

          {:ok, _other_event} ->
            # Not our response, keep waiting
            wait_for_embedding(conn, reference_id, timeout)

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end
    after
      timeout ->
        Gnat.unsub(conn, self(), "events.llm.embedding.created")
        Logger.warning("[Embedder] Embed request timed out after #{timeout}ms")
        {:error, :timeout}
    end
  end
end
