defmodule BotArmyInternalDocs.Stores.DocChunkStoreTest do
  use ExUnit.Case, async: false
  @moduletag :stores

  describe "API surface" do
    test "exports expected public functions" do
      funcs = [
        {BotArmyInternalDocs.Stores.DocChunkStore, :list, 0},
        {BotArmyInternalDocs.Stores.DocChunkStore, :list, 1},
        {BotArmyInternalDocs.Stores.DocChunkStore, :get, 1},
        {BotArmyInternalDocs.Stores.DocChunkStore, :create, 1},
        {BotArmyInternalDocs.Stores.DocChunkStore, :update, 2},
        {BotArmyInternalDocs.Stores.DocChunkStore, :upsert_chunk, 1},
        {BotArmyInternalDocs.Stores.DocChunkStore, :update_embedding, 2},
        {BotArmyInternalDocs.Stores.DocChunkStore, :search_by_vector, 2},
        {BotArmyInternalDocs.Stores.DocChunkStore, :mark_enriched, 3}
      ]

      for {mod, fun, arity} <- funcs do
        Code.ensure_loaded(mod)

        assert function_exported?(mod, fun, arity),
               "Expected #{inspect(mod)}.#{fun}/#{arity} to be exported"
      end
    end
  end
end
