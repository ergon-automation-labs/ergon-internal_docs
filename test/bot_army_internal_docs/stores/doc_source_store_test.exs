defmodule DocSourceStoreTest do
  use ExUnit.Case, async: false
  @moduletag :stores

  alias DocSourceStore

  # Phase 1: unit tests without DB (store requires Repo)
  # Integration tests will run with real DB when configured

  describe "API surface" do
    test "exports expected public functions" do
      funcs = [
        {DocSourceStore, :list, 0},
        {DocSourceStore, :get, 1},
        {DocSourceStore, :create, 1},
        {DocSourceStore, :update, 2},
        {DocSourceStore, :remove, 1},
        {DocSourceStore, :get_by_location, 1},
        {DocSourceStore, :enable, 1},
        {DocSourceStore, :disable, 1}
      ]

      for {mod, fun, arity} <- funcs do
        Code.ensure_loaded(mod)

        assert function_exported?(mod, fun, arity),
               "Expected #{inspect(mod)}.#{fun}/#{arity} to be exported"
      end
    end
  end

  describe "bootstrap_sources/0" do
    setup do
      prev_defaults = Application.get_env(:bot_army_internal_docs, :default_sources)
      prev_para_path = Application.get_env(:bot_army_internal_docs, :para_docs_path)

      on_exit(fn ->
        Application.put_env(:bot_army_internal_docs, :default_sources, prev_defaults)
        Application.put_env(:bot_army_internal_docs, :para_docs_path, prev_para_path)
      end)

      :ok
    end

    test "adds para local source when para path exists" do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "internal_docs_para_test_#{System.unique_integer([:positive])}"
        )

      para_path = Path.join(tmp, "docs/personal_os")
      File.mkdir_p!(para_path)

      Application.put_env(:bot_army_internal_docs, :default_sources, [])
      Application.put_env(:bot_army_internal_docs, :para_docs_path, para_path)

      sources = DocSourceStore.bootstrap_sources()

      assert Enum.any?(sources, fn source ->
               source["location"] == Path.expand(para_path) and
                 source["source_type"] == "local_file" and
                 source["name"] == "personal_os_docs"
             end)
    end

    test "does not duplicate location when para path is already configured" do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "internal_docs_para_test_#{System.unique_integer([:positive])}"
        )

      para_path = Path.join(tmp, "docs/personal_os")
      File.mkdir_p!(para_path)

      source = %{
        "source_type" => "local_file",
        "location" => Path.expand(para_path),
        "name" => "existing_docs_source"
      }

      Application.put_env(:bot_army_internal_docs, :default_sources, [source])
      Application.put_env(:bot_army_internal_docs, :para_docs_path, para_path)

      sources = DocSourceStore.bootstrap_sources()

      same_location_count =
        sources
        |> Enum.count(fn item -> item["location"] == Path.expand(para_path) end)

      assert same_location_count == 1
    end
  end
end
