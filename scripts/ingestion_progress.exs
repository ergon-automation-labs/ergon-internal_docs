#!/usr/bin/env elixir

alias BotArmyInternalDocs.{Repo, Schemas}
import Ecto.Query

tenant_id = "00000000-0000-0000-0000-000000000001"

total =
  Repo.aggregate(
    from(c in Schemas.DocChunk, where: c.tenant_id == ^tenant_id),
    :count
  )

embedded =
  Repo.aggregate(
    from(c in Schemas.DocChunk, where: c.tenant_id == ^tenant_id and not is_nil(c.embedded_at)),
    :count
  )

pending = total - embedded
pct = if total > 0, do: round(embedded / total * 100), else: 0
filled = div(pct, 5)
empty = 20 - filled
bar = String.duplicate("█", filled) <> String.duplicate("░", empty)

IO.puts("📊 Embedding Progress")
IO.puts("─────────────────────")
IO.puts("Total chunks:   #{total}")
IO.puts("Embedded:       #{embedded}")
IO.puts("Pending:        #{pending}")
IO.puts("Progress:       #{pct}%")
IO.puts("")
IO.puts("[#{bar}] #{pct}%")
