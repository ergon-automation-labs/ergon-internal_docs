#!/usr/bin/env elixir

alias BotArmyInternalDocs.{Repo, Schemas}
import Ecto.Query

tenant_id = "00000000-0000-0000-0000-000000000001"

sources = Repo.all(from(s in Schemas.DocSource, where: s.tenant_id == ^tenant_id))

IO.puts("📋 Doc Sources & Indexing Status")
IO.puts("────────────────────────────────")
IO.puts("")

Enum.each(sources, fn s ->
  chunks =
    Repo.aggregate(
      from(c in Schemas.DocChunk, where: c.source_id == ^s.id),
      :count
    )

  embedded =
    Repo.aggregate(
      from(c in Schemas.DocChunk, where: c.source_id == ^s.id and not is_nil(c.embedded_at)),
      :count
    )

  status = if s.enabled, do: "✓", else: "✗"

  IO.puts("#{status} #{s.name}")
  IO.puts("   Location: #{s.location}")
  IO.puts("   Chunks: #{chunks} (#{embedded} embedded)")
  IO.puts("")
end)

total_chunks =
  Repo.aggregate(
    from(c in Schemas.DocChunk, where: c.tenant_id == ^tenant_id),
    :count
  )

total_embedded =
  Repo.aggregate(
    from(c in Schemas.DocChunk, where: c.tenant_id == ^tenant_id and not is_nil(c.embedded_at)),
    :count
  )

IO.puts("Summary")
IO.puts("─────────────────────────────────")
IO.puts("Total chunks: #{total_chunks}")
IO.puts("Total embedded: #{total_embedded}")
