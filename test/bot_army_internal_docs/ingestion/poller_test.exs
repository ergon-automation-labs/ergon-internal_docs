defmodule BotArmyInternalDocs.Ingestion.PollerTest do
  use ExUnit.Case
  @moduletag :ingestion

  test "Poller module exports run_fetch/0 and run_fetch/1" do
    Code.ensure_loaded(BotArmyInternalDocs.Ingestion.Poller)

    assert function_exported?(BotArmyInternalDocs.Ingestion.Poller, :run_fetch, 0)
    assert function_exported?(BotArmyInternalDocs.Ingestion.Poller, :run_fetch, 1)
  end
end
