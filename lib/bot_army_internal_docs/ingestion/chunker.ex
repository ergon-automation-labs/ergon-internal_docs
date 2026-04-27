defmodule BotArmyInternalDocs.Ingestion.Chunker do
  @moduledoc false
  require Logger

  alias BotArmyInternalDocs.Stores.DocChunkStore
  alias BotArmyInternalDocs.NATS.Publisher

  @max_chunk_bytes 2048

  def chunk_document(%{content: content, path: path, name: name}, source_id) do
    tenant_id = "00000000-0000-0000-0000-000000000001"

    sections = split_by_headings(content)

    sections
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {section, idx} ->
      section_chunks =
        section.content
        |> split_large_section()
        |> Enum.with_index(0)

      Enum.flat_map(section_chunks, fn {chunk_content, sub_idx} ->
        if String.trim(chunk_content) == "" do
          []
        else
          chunk_index = idx * 100 + sub_idx
          content_hash = :crypto.hash(:sha256, chunk_content) |> Base.encode16(case: :lower)

          attrs = %{
            source_id: source_id,
            content: chunk_content,
            content_hash: content_hash,
            chunk_index: chunk_index,
            heading: section.heading,
            enrichment_status: "pending",
            metadata: %{path: path, name: name},
            tenant_id: tenant_id
          }

          case DocChunkStore.upsert_chunk(attrs) do
            {:ok, chunk, :new} ->
              Logger.debug("[Chunker] New chunk #{chunk.id} from #{name} (idx #{chunk_index})")
              Publisher.publish_chunk_ingested(chunk, %{name: name})
              [chunk]

            {:ok, _chunk, :existing} ->
              Logger.debug("[Chunker] Existing chunk from #{name} (idx #{chunk_index}), skipping")
              []

            {:error, changeset} ->
              Logger.warning("[Chunker] Failed to store chunk: #{inspect(changeset.errors)}")
              []
          end
        end
      end)
    end)
    |> List.flatten()
  end

  defp split_by_headings(content) do
    lines = String.split(content, "\n")

    {sections, current} =
      Enum.reduce(lines, {[], %{heading: nil, content: ""}}, fn line,
                                                                {sections_acc, current_acc} ->
        cond do
          Regex.match?(~R/^#{1,6}\s+/, line) ->
            heading = line |> String.replace(~R/^#{1,6}\s+/, "") |> String.trim()

            if current_acc.content == "" and is_nil(current_acc.heading) do
              {sections_acc, %{heading: heading, content: ""}}
            else
              {sections_acc ++ [current_acc], %{heading: heading, content: ""}}
            end

          true ->
            trimmed = String.trim(line)

            if trimmed == "" and current_acc.content == "" do
              {sections_acc, current_acc}
            else
              new_content =
                if current_acc.content == "",
                  do: trimmed,
                  else: current_acc.content <> "\n" <> trimmed

              {sections_acc, %{current_acc | content: new_content}}
            end
        end
      end)

    if current.content != "" or is_nil(current.heading) do
      sections ++ [current]
    else
      sections
    end
  end

  defp split_large_section(content) when byte_size(content) <= @max_chunk_bytes do
    [content]
  end

  defp split_large_section(content) do
    paragraphs = String.split(content, ~r/\n\n+/)
    chunk_paragraphs(paragraphs, [], "")
  end

  defp chunk_paragraphs([], chunks, current) do
    if current == "", do: chunks, else: chunks ++ [current]
  end

  defp chunk_paragraphs([para | rest], chunks, current) do
    candidate = if current == "", do: para, else: current <> "\n\n" <> para

    cond do
      current == "" and byte_size(para) > @max_chunk_bytes ->
        hard_split = split_by_sentence(para)
        chunk_paragraphs(rest, chunks ++ hard_split, "")

      byte_size(candidate) <= @max_chunk_bytes ->
        chunk_paragraphs(rest, chunks, candidate)

      true ->
        new_chunks = if current != "", do: chunks ++ [current], else: chunks
        chunk_paragraphs(rest, new_chunks, para)
    end
  end

  defp split_by_sentence(text) do
    text
    |> String.split(~r/(?<=[.!?])\s+/)
    |> chunk_sentences([], "")
  end

  defp chunk_sentences([], chunks, current) do
    if current == "", do: chunks, else: chunks ++ [current]
  end

  defp chunk_sentences([sentence | rest], chunks, current) do
    candidate = if current == "", do: sentence, else: current <> " " <> sentence

    if byte_size(candidate) <= @max_chunk_bytes do
      chunk_sentences(rest, chunks, candidate)
    else
      new_chunks = if current != "", do: chunks ++ [current], else: chunks
      chunk_sentences(rest, new_chunks, sentence)
    end
  end
end
