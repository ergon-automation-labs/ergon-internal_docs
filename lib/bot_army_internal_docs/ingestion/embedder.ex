defmodule BotArmyInternalDocs.Ingestion.Embedder do
  @moduledoc false
  require Logger

  @default_model "nomic-embed-text"
  @ollama_url "http://localhost:11434/api/embed"
  @timeout_ms 30_000

  def embed(text, model \\ nil) do
    model = model || @default_model
    body = Jason.encode!(%{model: model, input: text})

    headers = [{"Content-Type", "application/json"}]

    case :httpc.request(
           :post,
           {String.to_charlist(@ollama_url), headers, "application/json", body},
           [{:timeout, @timeout_ms}],
           [{:body_format, :binary}]
         ) do
      {:ok, {{_http, 200, _}, _resp_headers, resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"embeddings" => [vector | _]}} ->
            {:ok, vector}

          {:ok, other} ->
            Logger.warning("[Embedder] Unexpected response: #{inspect(other)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:ok, {{_http, status, _}, _headers, _body}} ->
        Logger.warning("[Embedder] Ollama HTTP #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("[Embedder] Ollama request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
