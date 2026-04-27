defmodule BotArmyInternalDocs.Ingestion.EmbedWorkerTest do
  use ExUnit.Case
  @moduletag :ingestion

  test "EmbedWorker module exports queue_chunk/1 and queue_chunks/1" do
    Code.ensure_loaded(BotArmyInternalDocs.Ingestion.EmbedWorker)

    assert function_exported?(BotArmyInternalDocs.Ingestion.EmbedWorker, :queue_chunk, 1)
    assert function_exported?(BotArmyInternalDocs.Ingestion.EmbedWorker, :queue_chunks, 1)
  end
end
