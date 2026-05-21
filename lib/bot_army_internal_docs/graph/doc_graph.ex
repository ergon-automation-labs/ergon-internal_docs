defmodule BotArmyInternalDocs.Graph.DocGraph do
  @moduledoc """
  Graph operations for document relationships via Apache AGE.
  Syncs DocSource and DocChunk records to the knowledge graph.
  """

  require Logger

  alias BotArmy.Graph

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
    Logger.debug("[DocGraph] Phase 4 stub")
    {:ok, []}
  end

  def keyword_search(_query, _limit) do
    Logger.debug("[DocGraph] Phase 4 stub")
    {:ok, []}
  end

  defp escape_string(s) when is_binary(s) do
    String.replace(s, "'", "''")
  end

  defp escape_label(label) when is_binary(label) do
    String.replace(label, ~r/[^a-zA-Z0-9_]/, "")
  end
end
