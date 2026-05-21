defmodule BotArmyInternalDocs.Ingestion.Fetchers.LocalFile do
  @moduledoc false
  require Logger

  @extensions ~w(.md .txt .rst .markdown .pdf)
  @default_max_text_bytes 15 * 1024 * 1024
  @default_max_pdf_bytes 50 * 1024 * 1024

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
            {:ok, _} ->
              true

            {:error, reason} ->
              Logger.debug("[LocalFile] Skipping #{inspect(reason)}")
              false
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
    ext = Path.extname(path)

    with :ok <- ensure_within_size(path, ext),
         {:ok, content} <- read_content(path, ext) do
      {:ok,
       %{
         content: content,
         path: path,
         name: Path.basename(path),
         extension: ext,
         modified_at: file_mtime(path)
       }}
    end
  end

  defp read_content(path, ".pdf"), do: extract_pdf_text(path)

  defp read_content(path, _ext) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  defp extract_pdf_text(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, {:pdf_extractor_unavailable, path}}

      bin ->
        case System.cmd(bin, ["-q", path, "-"], stderr_to_stdout: true) do
          {text, 0} ->
            cleaned = String.trim(text)

            if cleaned == "" do
              {:error, {:pdf_empty_text, path}}
            else
              {:ok, cleaned}
            end

          {output, status} ->
            {:error, {:pdf_extract_failed, path, status, String.slice(output, 0, 200)}}
        end
    end
  end

  defp ensure_within_size(path, ext) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        if size <= max_bytes_for_ext(ext) do
          :ok
        else
          {:error, {:file_too_large, path, size}}
        end

      {:error, reason} ->
        {:error, {:stat_failed, path, reason}}
    end
  end

  defp max_bytes_for_ext(".pdf"),
    do: env_int("BOT_ARMY_INTERNAL_DOCS_MAX_PDF_BYTES", @default_max_pdf_bytes)

  defp max_bytes_for_ext(_),
    do: env_int("BOT_ARMY_INTERNAL_DOCS_MAX_TEXT_BYTES", @default_max_text_bytes)

  defp env_int(name, default) do
    case System.get_env(name) do
      nil ->
        default

      raw ->
        case Integer.parse(String.trim(raw)) do
          {value, _} when value > 0 -> value
          _ -> default
        end
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
