defmodule BotArmyInternalDocs.Graph.DocGraph do
  @moduledoc """
  Graph operations for document relationships via Apache AGE.
  Syncs DocSource and DocChunk records to the knowledge graph.
  """

  require Logger

  alias BotArmy.Graph
  alias BotArmyInternalDocs.Stores.DocChunkStore

  def upsert_doc_node(id, name, properties \\ %{}) do
    location = properties[:path] || ""
    source_type = properties[:source_type] || "local_file"
    category = properties[:category] || "general"

    cypher =
      "MERGE (d:Doc {id: '#{escape_string(id)}'}) " <>
        "SET d.name = '#{escape_string(name)}', " <>
        "d.location = '#{escape_string(location)}', " <>
        "d.source_type = '#{escape_string(source_type)}', " <>
        "d.category = '#{escape_string(category)}', " <>
        "d.updated_at = timestamp()"

    case Graph.query(cypher) do
      {:ok, _} ->
        :ok

      {:error, e} ->
        Logger.warning("[DocGraph] upsert_doc_node failed: #{inspect(e)}")
        :ok
    end
  end

  def upsert_chunk_node(id, heading, properties \\ %{}) do
    heading_str = heading || ""
    chunk_index = properties[:chunk_index] || 0
    enrichment_status = properties[:enrichment_status] || "pending"

    cypher =
      "MERGE (c:DocChunk {id: '#{escape_string(id)}'}) " <>
        "SET c.heading = '#{escape_string(heading_str)}', " <>
        "c.chunk_index = #{chunk_index}, " <>
        "c.enrichment_status = '#{escape_string(enrichment_status)}', " <>
        "c.updated_at = timestamp()"

    case Graph.query(cypher) do
      {:ok, _} ->
        :ok

      {:error, e} ->
        Logger.warning("[DocGraph] upsert_chunk_node failed: #{inspect(e)}")
        :ok
    end
  end

  def create_relationship(from_id, to_id, type, _properties \\ %{}) do
    relationship_type = escape_label(type)

    cypher =
      "MATCH (from {id: '#{escape_string(from_id)}'}) " <>
        "MATCH (to {id: '#{escape_string(to_id)}'}) " <>
        "MERGE (from)-[r:#{relationship_type}]->(to) " <>
        "SET r.updated_at = timestamp()"

    case Graph.query(cypher) do
      {:ok, _} ->
        :ok

      {:error, e} ->
        Logger.warning("[DocGraph] create_relationship failed: #{inspect(e)}")
        :ok
    end
  end

  def semantic_search(_query_vector, _limit) do
    Logger.debug("[DocGraph] Phase 5 stub — requires AGE pgvector extension")
    {:ok, []}
  end

  def keyword_search(query, limit) do
    # Graph: match headings via Cypher
    cypher =
      "MATCH (c:DocChunk) WHERE c.heading CONTAINS '#{escape_string(query)}' RETURN c.id::text LIMIT #{limit}"

    sql = "SELECT chunk_id::text FROM cypher('knowledge', $1) AS (chunk_id agtype)"

    graph_ids =
      case BotArmyInternalDocs.GraphRepo.query(sql, [cypher]) do
        {:ok, result} ->
          result.rows
          |> Enum.map(fn [id] -> decode_agtype(id) end)

        _ ->
          []
      end

    # PostgreSQL: full-text content search
    pg_ids =
      case DocChunkStore.search_by_keyword(query, limit) do
        {:ok, chunks} -> Enum.map(chunks, & &1.id)
        _ -> []
      end

    # Merge: graph heading matches first (prioritized), then PostgreSQL content matches
    merged_ids = (graph_ids ++ pg_ids) |> Enum.uniq() |> Enum.take(limit)
    {:ok, merged_ids}
  end

  def get_doc_context(chunk_id) do
    cypher = """
    MATCH (d:Doc)-[:HAS_CHUNK]->(target:DocChunk {id: '#{escape_string(chunk_id)}'})
    MATCH (d)-[:HAS_CHUNK]->(sibling:DocChunk)
    WHERE sibling.chunk_index >= target.chunk_index - 2
      AND sibling.chunk_index <= target.chunk_index + 2
    RETURN d.id::text, d.name::text, d.location::text, d.source_type::text,
           sibling.id::text, sibling.heading::text, sibling.chunk_index::text
    """

    sql =
      "SELECT doc_id::text, doc_name::text, loc::text, stype::text, sib_id::text, sib_heading::text, sib_idx::text FROM cypher('knowledge', $1) AS (doc_id agtype, doc_name agtype, loc agtype, stype agtype, sib_id agtype, sib_heading agtype, sib_idx agtype)"

    case BotArmyInternalDocs.GraphRepo.query(sql, [cypher]) do
      {:ok, result} ->
        if Enum.empty?(result.rows) do
          {:error, :not_found}
        else
          {doc_info, siblings} = parse_doc_context_rows(result.rows)
          {:ok, Map.put(doc_info, :siblings, siblings)}
        end

      {:error, e} ->
        Logger.warning("[DocGraph] get_doc_context failed: #{inspect(e)}")
        {:error, :query_failed}
    end
  end

  defp parse_doc_context_rows([
         [doc_id, doc_name, loc, stype, sib_id, sib_heading, sib_idx] | rest
       ]) do
    doc_info = %{
      id: decode_agtype(doc_id),
      name: decode_agtype(doc_name),
      location: decode_agtype(loc),
      source_type: decode_agtype(stype)
    }

    siblings =
      [[doc_id, doc_name, loc, stype, sib_id, sib_heading, sib_idx] | rest]
      |> Enum.map(fn [_doc_id, _doc_name, _loc, _stype, s_id, s_heading, s_idx] ->
        %{
          id: decode_agtype(s_id),
          heading: decode_agtype(s_heading),
          chunk_index: decode_agtype(s_idx) |> to_integer()
        }
      end)
      |> Enum.uniq_by(& &1.id)

    {doc_info, siblings}
  end

  defp parse_doc_context_rows([]), do: {%{}, []}

  defp to_integer(nil), do: 0

  defp to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(int) when is_integer(int), do: int

  defp decode_agtype(nil), do: nil

  defp decode_agtype(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      _ -> raw
    end
  end

  defp escape_string(s) when is_binary(s) do
    String.replace(s, "'", "''")
  end

  defp escape_label(label) when is_binary(label) do
    String.replace(label, ~r/[^a-zA-Z0-9_]/, "")
  end
end
