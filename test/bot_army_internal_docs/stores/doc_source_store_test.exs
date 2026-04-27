defmodule BotArmyInternalDocs.Stores.DocSourceStoreTest do
  use ExUnit.Case, async: false
  @moduletag :stores

  # Phase 1: unit tests without DB (store requires Repo)
  # Integration tests will run with real DB when configured

  describe "API surface" do
    test "exports expected public functions" do
      funcs = [
        {BotArmyInternalDocs.Stores.DocSourceStore, :list, 0},
        {BotArmyInternalDocs.Stores.DocSourceStore, :get, 1},
        {BotArmyInternalDocs.Stores.DocSourceStore, :create, 1},
        {BotArmyInternalDocs.Stores.DocSourceStore, :update, 2},
        {BotArmyInternalDocs.Stores.DocSourceStore, :remove, 1},
        {BotArmyInternalDocs.Stores.DocSourceStore, :get_by_location, 1},
        {BotArmyInternalDocs.Stores.DocSourceStore, :enable, 1},
        {BotArmyInternalDocs.Stores.DocSourceStore, :disable, 1}
      ]

      for {mod, fun, arity} <- funcs do
        Code.ensure_loaded(mod)

        assert function_exported?(mod, fun, arity),
               "Expected #{inspect(mod)}.#{fun}/#{arity} to be exported"
      end
    end
  end
end
