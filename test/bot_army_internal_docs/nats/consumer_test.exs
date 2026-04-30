defmodule BotArmyInternalDocs.NATS.ConsumerTest do
  use ExUnit.Case
  @moduletag :nats

  alias BotArmyInternalDocs.NATS.Consumer

  describe "embedding_chunk_id/1" do
    test "prefers chunk_id when present" do
      payload = %{
        "chunk_id" => "chunk-123",
        "reference_id" => "ref-123",
        "card_id" => "card-123"
      }

      assert Consumer.embedding_chunk_id(payload) == "chunk-123"
    end

    test "falls back to reference_id then card_id" do
      assert Consumer.embedding_chunk_id(%{"reference_id" => "ref-123"}) == "ref-123"
      assert Consumer.embedding_chunk_id(%{"card_id" => "card-123"}) == "card-123"
    end

    test "returns nil when no compatible key is present" do
      assert Consumer.embedding_chunk_id(%{"foo" => "bar"}) == nil
    end
  end
end
