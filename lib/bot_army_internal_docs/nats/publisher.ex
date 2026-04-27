defmodule BotArmyInternalDocs.NATS.Publisher do
  alias BotArmyRuntime.NATS.Publisher

  def publish_source_added(source) do
    event = %{
      "event" => "events.internal_docs.source.added",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "payload" => %{
        "source_id" => source.id,
        "name" => source.name,
        "source_type" => source.source_type,
        "location" => source.location
      }
    }

    Publisher.publish("events.internal_docs.source.added", event)
  end

  def publish_chunk_ingested(chunk, source) do
    event = %{
      "event" => "events.internal_docs.chunk.ingested",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "payload" => %{
        "chunk_id" => chunk.id,
        "source_id" => chunk.source_id,
        "source_name" => source.name,
        "chunk_index" => chunk.chunk_index,
        "heading" => chunk.heading
      }
    }

    Publisher.publish("events.internal_docs.chunk.ingested", event)
  end

  def publish_doc_enriched(chunk, source) do
    event = %{
      "event" => "events.internal_docs.doc.enriched",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "payload" => %{
        "chunk_id" => chunk.id,
        "source_id" => chunk.source_id,
        "source_name" => source.name,
        "topics" => chunk.topics,
        "summary" => chunk.summary
      }
    }

    Publisher.publish("events.internal_docs.doc.enriched", event)
  end

  def request_embedding(chunk_id, content) do
    event = %{
      "event" => "llm.embed.request",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "payload" => %{
        "reference_id" => chunk_id,
        "content" => content,
        "model" => "nomic-embed-text"
      }
    }

    Publisher.publish("llm.embed.request", event)
  end

  def request_enrichment(chunk_id, content) do
    event = %{
      "event" => "llm.inference.chain",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_internal_docs",
      "payload" => %{
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
      }
    }

    Publisher.publish("llm.inference.chain", event)
  end
end
