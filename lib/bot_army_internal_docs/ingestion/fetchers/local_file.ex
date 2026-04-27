defmodule BotArmyInternalDocs.Ingestion.Fetchers.LocalFile do
  @moduledoc false
  require Logger

  @extensions ~w(.md .txt .rst .markdown)

  def fetch(location) do
    path = Path.expand(location)

    cond do
      not File.exists?(path) ->
        {:error, {:path_not_found, path}}

      File.dir?(path) ->
        fetch_directory(path)

      true ->
        fetch_file(path)
    end
  end

  defp fetch_directory(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        documents =
          entries
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&File.regular?/1)
          |> Enum.filter(&has_extension?/1)
          |> Enum.map(&read_file/1)
          |> Enum.filter(fn
            {:ok, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:ok, doc} -> doc end)

        walk_subdirectories(dir, documents)

      {:error, reason} ->
        {:error, {:list_dir_failed, dir, reason}}
    end
  end

  defp walk_subdirectories(dir, documents) do
    case File.ls(dir) do
      {:ok, entries} ->
        subdocs =
          entries
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&File.dir?/1)
          |> Enum.reduce(documents, fn subdir, acc ->
            case fetch_directory(subdir) do
              {:ok, sub_documents} -> acc ++ sub_documents
              {:error, _} -> acc
            end
          end)

        {:ok, subdocs}

      {:error, _} ->
        {:ok, documents}
    end
  end

  defp fetch_file(path) do
    if has_extension?(path) do
      case read_file(path) do
        {:ok, doc} -> {:ok, [doc]}
        error -> error
      end
    else
      {:error, {:unsupported_extension, path}}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok,
         %{
           content: content,
           path: path,
           name: Path.basename(path),
           extension: Path.extname(path),
           modified_at: file_mtime(path)
         }}

      {:error, reason} ->
        Logger.warning("[LocalFile] Failed to read #{path}: #{inspect(reason)}")
        {:error, {:read_failed, path, reason}}
    end
  end

  defp has_extension?(path) do
    Path.extname(path) in @extensions
  end

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: {megabytes, seconds, _microseconds}}} ->
        epoch = megabytes * 1_000_000 + seconds
        DateTime.from_unix!(epoch)

      _ ->
        DateTime.utc_now()
    end
  end
end
