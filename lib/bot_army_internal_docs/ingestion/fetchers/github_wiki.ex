defmodule BotArmyInternalDocs.Ingestion.Fetchers.GitHubWiki do
  @moduledoc "Fetches documentation from GitHub repository wikis and markdown files via GitHub API."
  require Logger

  @markdown_extensions ~w(.md .markdown)
  @default_max_bytes 10 * 1024 * 1024

  def fetch(location) do
    case parse_github_url(location) do
      {:ok, {owner, repo, path}} ->
        fetch_from_github(owner, repo, path)

      {:error, reason} ->
        {:error, {:invalid_github_url, location, reason}}
    end
  end

  defp parse_github_url(location) do
    case String.split(location, "/") do
      [owner, repo] ->
        {:ok, {owner, repo, ""}}

      [owner, repo, "tree", _branch | rest] ->
        path = Enum.join(rest, "/")
        {:ok, {owner, repo, path}}

      [owner, repo | _rest] ->
        {:ok, {owner, repo, ""}}

      _ ->
        {:error, "Invalid GitHub URL format. Use: owner/repo or owner/repo/tree/branch/path"}
    end
  end

  defp fetch_from_github(owner, repo, path) do
    token = System.get_env("GITHUB_TOKEN")

    case fetch_repo_contents(owner, repo, path, token) do
      {:ok, items} ->
        documents =
          items
          |> Enum.filter(&markdown?/1)
          |> Enum.map(&fetch_file_content(&1, owner, repo, token))
          |> Enum.filter(fn
            {:ok, _} ->
              true

            {:error, reason} ->
              Logger.debug("[GitHubWiki] Skipping file: #{inspect(reason)}")
              false
          end)
          |> Enum.map(fn {:ok, doc} -> doc end)

        {:ok, documents}

      {:error, reason} ->
        {:error, {:github_fetch_failed, "#{owner}/#{repo}", reason}}
    end
  end

  defp fetch_repo_contents(owner, repo, path, token) do
    url = build_api_url(owner, repo, path)
    headers = build_headers(token)

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_list(data) ->
            {:ok, data}

          {:ok, data} when is_map(data) ->
            {:ok, [data]}

          {:error, reason} ->
            {:error, {:decode_failed, reason}}
        end

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_file_content(%{"name" => name, "download_url" => url}, _owner, _repo, _token)
       when is_binary(url) and url != "" do
    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: content}} ->
        case ensure_within_size(content) do
          :ok ->
            {:ok,
             %{
               content: content,
               path: url,
               name: name,
               extension: Path.extname(name),
               modified_at: DateTime.utc_now()
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, {:download_error, reason}}
    end
  end

  defp fetch_file_content(%{"name" => name} = item, owner, repo, token) do
    case Map.get(item, "sha") do
      sha when is_binary(sha) ->
        case fetch_blob_content(owner, repo, sha, token) do
          {:ok, content} ->
            {:ok,
             %{
               content: content,
               path: Map.get(item, "path", name),
               name: name,
               extension: Path.extname(name),
               modified_at: DateTime.utc_now()
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, {:missing_sha, name}}
    end
  end

  defp fetch_blob_content(owner, repo, sha, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/blobs/#{sha}"
    headers = build_headers(token)

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"content" => encoded_content}} ->
            case Base.decode64(encoded_content) do
              {:ok, content} -> {:ok, content}
              :error -> {:error, :base64_decode_failed}
            end

          {:error, reason} ->
            {:error, {:decode_failed, reason}}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp build_api_url(owner, repo, "") do
    "https://api.github.com/repos/#{owner}/#{repo}/contents"
  end

  defp build_api_url(owner, repo, path) do
    "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}"
  end

  defp build_headers(token) do
    headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"User-Agent", "BotArmyInternalDocs"}
    ]

    if token && token != "" do
      [{"Authorization", "token #{token}"} | headers]
    else
      headers
    end
  end

  defp markdown?(%{"type" => "file", "name" => name}) do
    Path.extname(name) in @markdown_extensions
  end

  defp markdown?(_), do: false

  defp ensure_within_size(content) when is_binary(content) do
    max_bytes = env_int("BOT_ARMY_INTERNAL_DOCS_MAX_TEXT_BYTES", @default_max_bytes)

    if byte_size(content) <= max_bytes do
      :ok
    else
      {:error, {:content_too_large, byte_size(content)}}
    end
  end

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
end
