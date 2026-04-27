defmodule BotArmyInternalDocs.Ingestion.Fetchers.LocalFileTest do
  use ExUnit.Case
  @moduletag :ingestion

  alias BotArmyInternalDocs.Ingestion.Fetchers.LocalFile

  @tmp_dir Path.join(System.tmp_dir!(), "internal_docs_test_#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
    end)

    :ok
  end

  describe "fetch/1" do
    test "reads a single markdown file" do
      path = Path.join(@tmp_dir, "test.md")
      File.write!(path, "# Hello\n\nWorld")

      assert {:ok, [doc]} = LocalFile.fetch(path)
      assert doc.content == "# Hello\n\nWorld"
      assert doc.name == "test.md"
      assert doc.extension == ".md"
    end

    test "reads a single text file" do
      path = Path.join(@tmp_dir, "notes.txt")
      File.write!(path, "Some notes")

      assert {:ok, [doc]} = LocalFile.fetch(path)
      assert doc.content == "Some notes"
      assert doc.name == "notes.txt"
      assert doc.extension == ".txt"
    end

    test "reads a directory of markdown files" do
      File.write!(Path.join(@tmp_dir, "a.md"), "Doc A")
      File.write!(Path.join(@tmp_dir, "b.md"), "Doc B")
      File.write!(Path.join(@tmp_dir, "ignore.ex"), "code()")

      assert {:ok, docs} = LocalFile.fetch(@tmp_dir)
      assert length(docs) == 2
      assert Enum.map(docs, & &1.name) |> Enum.sort() == ["a.md", "b.md"]
    end

    test "walks subdirectories" do
      subdir = Path.join(@tmp_dir, "sub")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "deep.md"), "Deep doc")

      assert {:ok, [doc]} = LocalFile.fetch(@tmp_dir)
      assert doc.name == "deep.md"
    end

    test "returns error for nonexistent path" do
      assert {:error, {:path_not_found, _}} = LocalFile.fetch("/nonexistent/path")
    end

    test "skips unsupported file extensions" do
      path = Path.join(@tmp_dir, "image.png")
      File.write!(path, <<0, 1, 2, 3>>)

      assert {:error, {:unsupported_extension, _}} = LocalFile.fetch(path)
    end
  end
end
