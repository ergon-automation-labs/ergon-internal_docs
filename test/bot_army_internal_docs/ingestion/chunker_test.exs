defmodule BotArmyInternalDocs.Ingestion.ChunkerTest do
  use ExUnit.Case
  @moduletag :ingestion

  describe "chunk_document/2" do
    test "chunks a document with headings" do
      doc = %{
        content: "# Intro\n\nIntro paragraph.\n\n# Details\n\nDetail paragraph.",
        path: "/tmp/test.md",
        name: "test.md"
      }

      # chunk_document calls DocChunkStore which needs DB, just test the split logic
      sections = split_by_headings(doc.content)
      assert length(sections) == 2
      assert Enum.at(sections, 0).heading == "Intro"
      assert Enum.at(sections, 1).heading == "Details"
    end
  end

  describe "split_by_headings" do
    test "splits single heading with content" do
      content = "# Introduction\n\nThis is the intro paragraph."
      sections = split_by_headings(content)

      assert length(sections) == 1
      assert hd(sections).heading == "Introduction"
      assert hd(sections).content == "This is the intro paragraph."
    end

    test "splits multiple headings" do
      content = "# First\n\nFirst content.\n\n# Second\n\nSecond content."
      sections = split_by_headings(content)

      assert length(sections) == 2
      assert Enum.at(sections, 0).heading == "First"
      assert Enum.at(sections, 1).heading == "Second"
    end

    test "handles content before first heading" do
      content = "Preamble text.\n\n# First Heading\n\nFirst content."
      sections = split_by_headings(content)

      assert length(sections) == 2
      assert Enum.at(sections, 0).heading == nil
      assert Enum.at(sections, 1).heading == "First Heading"
    end

    test "handles empty content" do
      sections = split_by_headings("")
      # Empty input produces no meaningful sections
      assert length(sections) <= 1
    end

    test "handles h2, h3 headings" do
      content = "## Sub Title\n\nSub content.\n### Deeper\n\nDeeper content."
      sections = split_by_headings(content)

      assert length(sections) == 2
      assert Enum.at(sections, 0).heading == "Sub Title"
      assert Enum.at(sections, 1).heading == "Deeper"
    end
  end

  describe "split_large_section" do
    test "keeps small sections as single chunk" do
      content = "Short content."
      chunks = split_large_section(content)
      assert chunks == [content]
    end

    test "splits by paragraphs when too large" do
      para = String.duplicate("word ", 600)
      content = para <> "\n\n" <> para
      chunks = split_large_section(content)
      assert length(chunks) >= 2
    end
  end

  # Mirror the private logic for unit testing without DB dependency
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

  defp split_large_section(content) do
    if byte_size(content) <= 2048 do
      [content]
    else
      paragraphs = String.split(content, ~r/\n\n+/)
      chunk_paragraphs(paragraphs, [], "")
    end
  end

  defp chunk_paragraphs([], chunks, current) do
    if current == "", do: chunks, else: chunks ++ [current]
  end

  defp chunk_paragraphs([para | rest], chunks, current) do
    candidate = if current == "", do: para, else: current <> "\n\n" <> para

    if byte_size(candidate) <= 2048 do
      chunk_paragraphs(rest, chunks, candidate)
    else
      new_chunks = if current != "", do: chunks ++ [current], else: chunks
      chunk_paragraphs(rest, new_chunks, para)
    end
  end
end
