defmodule BotArmyInternalDocs.Graph.DocGraph do
  @moduledoc """
  Phase 3: Graph operations for document relationships via Apache AGE.
  """

  require Logger

  def upsert_doc_node(_id, _name, _properties) do
    Logger.debug("[DocGraph] Phase 3 stub")
    :ok
  end

  def upsert_chunk_node(_id, _heading, _properties) do
    Logger.debug("[DocGraph] Phase 3 stub")
    :ok
  end

  def create_relationship(_from_id, _to_id, _type, _properties) do
    Logger.debug("[DocGraph] Phase 3 stub")
    :ok
  end

  def semantic_search(_query_vector, _limit) do
    Logger.debug("[DocGraph] Phase 4 stub")
    {:ok, []}
  end

  def keyword_search(_query, _limit) do
    Logger.debug("[DocGraph] Phase 4 stub")
    {:ok, []}
  end
end
