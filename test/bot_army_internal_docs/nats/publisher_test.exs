defmodule BotArmyInternalDocs.NATS.PublisherTest do
  use ExUnit.Case
  @moduletag :nats

  describe "API surface" do
    test "exports expected public functions" do
      funcs = [
        {BotArmyInternalDocs.NATS.Publisher, :publish_source_added, 1},
        {BotArmyInternalDocs.NATS.Publisher, :publish_chunk_ingested, 2},
        {BotArmyInternalDocs.NATS.Publisher, :publish_doc_enriched, 2},
        {BotArmyInternalDocs.NATS.Publisher, :request_embedding, 2},
        {BotArmyInternalDocs.NATS.Publisher, :request_enrichment, 2}
      ]

      for {mod, fun, arity} <- funcs do
        Code.ensure_loaded(mod)

        assert function_exported?(mod, fun, arity),
               "Expected #{inspect(mod)}.#{fun}/#{arity} to be exported"
      end
    end
  end
end
