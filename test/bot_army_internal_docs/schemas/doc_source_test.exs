defmodule BotArmyInternalDocs.Schemas.DocSourceTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyInternalDocs.Schemas.DocSource

  describe "changeset/2" do
    test "valid attributes create a valid changeset" do
      attrs = %{
        source_type: "local_file",
        location: "/opt/bot_army/docs",
        name: "Bot Army Docs",
        category: "internal",
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocSource.changeset(%DocSource{}, attrs)
      assert changeset.valid?
    end

    test "requires source_type, location, name, and tenant_id" do
      changeset = DocSource.changeset(%DocSource{}, %{})

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

      assert errors[:source_type]
      assert errors[:location]
      assert errors[:name]
      assert errors[:tenant_id]
    end

    test "validates source_type inclusion" do
      attrs = %{
        source_type: "invalid_type",
        location: "/some/path",
        name: "Test",
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocSource.changeset(%DocSource{}, attrs)
      refute changeset.valid?

      assert %{source_type: ["is invalid"]} =
               Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    end

    test "accepts all valid source types" do
      for source_type <- ~w(local_file github_wiki web_url) do
        attrs = %{
          source_type: source_type,
          location: "/test",
          name: "Test",
          tenant_id: "00000000-0000-0000-0000-000000000001"
        }

        changeset = DocSource.changeset(%DocSource{}, attrs)
        assert changeset.valid?
      end
    end

    test "validates name length" do
      attrs = %{
        source_type: "local_file",
        location: "/test",
        name: String.duplicate("x", 201),
        tenant_id: "00000000-0000-0000-0000-000000000001"
      }

      changeset = DocSource.changeset(%DocSource{}, attrs)
      refute changeset.valid?
    end
  end
end
