defmodule BotArmyInternalDocs.Schemas.DocChunkTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyInternalDocs.Schemas.DocChunk

  describe "changeset/2" do
    test "valid attributes create a valid changeset" do
      attrs = %{
        source_id: Ecto.UUID.generate(),
        content: "Some documentation content",
        content_hash:
          :crypto.hash(:sha256, "Some documentation content") |> Base.encode16(case: :lower),
        chunk_index: 0,
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocChunk.changeset(%DocChunk{}, attrs)
      assert changeset.valid?
    end

    test "requires source_id, content, content_hash, chunk_index, and tenant_id" do
      changeset = DocChunk.changeset(%DocChunk{}, %{})

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

      assert errors[:source_id]
      assert errors[:content]
      assert errors[:content_hash]
      assert errors[:chunk_index]
      assert errors[:tenant_id]
    end

    test "default enrichment_status is pending" do
      attrs = %{
        source_id: Ecto.UUID.generate(),
        content: "test",
        content_hash: "abc123",
        chunk_index: 0,
        enrichment_status: "pending",
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocChunk.changeset(%DocChunk{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :enrichment_status) == "pending"
    end

    test "optional heading field" do
      attrs = %{
        source_id: Ecto.UUID.generate(),
        content: "test content",
        content_hash: "abc123",
        chunk_index: 0,
        heading: "Installation Guide",
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocChunk.changeset(%DocChunk{}, attrs)
      assert changeset.valid?
    end
  end
end
