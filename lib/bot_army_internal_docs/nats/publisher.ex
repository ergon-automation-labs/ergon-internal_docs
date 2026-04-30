defmodule BotArmyInternalDocs.NATS.Publisher do
  alias BotArmyRuntime.NATS.Publisher

  defp base_event(event_name, triggered_by) do
    %{
      "event" => event_name,
      "event_id" => UUID.uuid4(),
      "schema_version" => "1.0",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => triggered_by
    }
  end

  def publish_source_added(source) do
    event =
      base_event("events.internal_docs.source.added", "internal_docs.doc_source_store")
      |> Map.put("payload", %{
        "source_id" => source.id,
        "name" => source.name,
        "source_type" => source.source_type,
        "location" => source.location
      })

    Publisher.publish("events.internal_docs.source.added", event)
  end

  def publish_chunk_ingested(chunk, source) do
    event =
      base_event("events.internal_docs.chunk.ingested", "internal_docs.chunker")
      |> Map.put("payload", %{
        "chunk_id" => chunk.id,
        "source_id" => chunk.source_id,
        "source_name" => source.name,
        "chunk_index" => chunk.chunk_index,
        "heading" => chunk.heading
      })

    Publisher.publish("events.internal_docs.chunk.ingested", event)
  end

  def publish_doc_enriched(chunk, source) do
    event =
      base_event("events.internal_docs.doc.enriched", "internal_docs.enrichment_worker")
      |> Map.put("payload", %{
        "chunk_id" => chunk.id,
        "source_id" => chunk.source_id,
        "source_name" => source.name,
        "topics" => chunk.topics,
        "summary" => chunk.summary
      })

    Publisher.publish("events.internal_docs.doc.enriched", event)
  end

  def request_embedding(chunk_id, content) do
    event =
      base_event("llm.embed.request", "internal_docs.embed_worker")
      |> Map.put("payload", %{
        "text" => content,
        "chunk_id" => chunk_id,
        "reference_id" => chunk_id,
        "model" => "nomic-embed-text"
      })

    Publisher.publish("llm.embed.request", event)
  end

  def request_enrichment(chunk_id, content) do
    event =
      base_event("llm.inference.chain", "internal_docs.enrichment_worker")
      |> Map.put("payload", %{
        "chain" => [
          %{
            "name" => "extract_topics",
            "input" => "Extract topics and a summary from this documentation:\n\n#{content}"
          }
        ],
        "context" => %{
          "reference_id" => chunk_id,
          "bot_id" => "internal_docs",
          "skill_type" => "markdown"
        }
      })

    Publisher.publish("llm.inference.chain", event)
  end
end
