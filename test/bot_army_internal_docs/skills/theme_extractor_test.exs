defmodule BotArmyInternalDocs.Skills.ThemeExtractorTest do
  use ExUnit.Case
  @moduletag :skills

  alias BotArmyInternalDocs.Skills.ThemeExtractor

  @fixture Path.join([__DIR__, "..", "..", "fixtures", "sample_sourcebook.txt"])

  describe "extract/2 with a stub LLM caller" do
    test "produces a theme map satisfying the Preset required-keys contract" do
      text = File.read!(@fixture)

      llm_caller = fn prompt ->
        cond do
          String.contains?(prompt, "core resolution mechanic") ->
            {:ok,
             ~s({"setting": "Verdant Hollow", "tone": "wary and folkloric", "mechanic": "1d12 + Aspect vs Reckoning"})}

          String.contains?(prompt, "vocabulary substitution") ->
            {:ok,
             ~s({"attack": "swing", "defend": "hold", "buff": "bless", "inspire": "call the chorus", "inspect": "read the omen", "negotiate": "barter", "hack": "pick the seal", "evade": "walk unseen", "skill": "ply the trade", "move": "stride"})}

          String.contains?(prompt, "NPC/faction archetypes") ->
            {:ok,
             """
             [
               {"key": "council_warden", "title": "Council Warden", "demeanor": "quiet, kind, last word", "carries": ["warrant", "baton"]},
               {"key": "hedgewitch", "title": "Hedgewitch", "demeanor": "brisk, unimpressed", "carries": ["herbs", "knife"]},
               {"key": "lordmagus", "title": "Lordmagus-At-Arms", "demeanor": "imperious, never refused", "carries": ["pistol", "parchment"]},
               {"key": "tor_shepherd", "title": "Tor-Shepherd", "demeanor": "weather-creased, patient", "carries": ["staff", "flute"]},
               {"key": "drowned_mason", "title": "Drowned-Mason", "demeanor": "unhurried, weighty quiet", "carries": ["plumb-line", "compass"]}
             ]
             """}

          String.contains?(prompt, "scene snippets") ->
            {:ok,
             ~s({"scene_intro": "Wet smell of peat smoke.", "combat_intro": "Crows lift in a single shape.", "rest_scene": "The hearth ticks.", "victory": "A careful inventory.", "defeat": "A long walk back."})}

          true ->
            {:error, :no_stub_for_prompt}
        end
      end

      assert {:ok, %{theme: theme, errors: [], warnings: []}} =
               ThemeExtractor.extract(text, llm_caller: llm_caller)

      assert theme["setting"] == "Verdant Hollow"
      assert theme["vocabulary"]["attack"] == "swing"
      assert map_size(theme["npc_personas"]) == 5
      assert theme["npc_personas"]["council_warden"]["title"] == "Council Warden"
      assert theme["templates"]["scene_intro"] == "Wet smell of peat smoke."
      assert is_list(theme["rules"]["action_types"])
      assert "attack" in theme["rules"]["action_types"]
    end

    test "tolerates markdown-fenced JSON responses" do
      text = "Some sourcebook text."

      llm_caller = fn prompt ->
        if String.contains?(prompt, "core resolution mechanic") do
          {:ok, ~s(```json\n{"setting": "X", "tone": "Y", "mechanic": "Z"}\n```)}
        else
          {:ok, "{}"}
        end
      end

      assert {:ok, %{theme: theme}} = ThemeExtractor.extract(text, llm_caller: llm_caller)
      assert theme["setting"] == "X"
      assert theme["tone"] == "Y"
      assert theme["mechanic"] == "Z"
    end

    test "surfaces errors when the LLM call fails" do
      text = "Some sourcebook text."
      llm_caller = fn _prompt -> {:error, :unavailable} end

      assert {:ok, %{theme: theme, errors: errors}} =
               ThemeExtractor.extract(text, llm_caller: llm_caller)

      assert length(errors) == 4
      assert theme["setting"] == "TODO"
      # vocabulary, templates fallback to filled-with-TODO maps
      assert theme["vocabulary"]["attack"] == "TODO"
      assert theme["templates"]["scene_intro"] == "TODO"
      assert theme["npc_personas"] == %{}
    end

    test "warns when LLM returns wrong shape" do
      text = "Some sourcebook text."
      llm_caller = fn _prompt -> {:ok, ~s({"this_is_not_what_we_asked_for": true})} end

      assert {:ok, %{theme: theme, warnings: warnings}} =
               ThemeExtractor.extract(text, llm_caller: llm_caller)

      assert warnings != []
      # When the setting step shape is wrong, we fall back to TODO
      assert theme["setting"] == "TODO"
    end

    test "passes the configured prompt budget through to the LLM" do
      text = String.duplicate("A", 100_000)

      received_prompts = :ets.new(:received_prompts, [:public])
      :ets.insert(received_prompts, {:count, 0})

      llm_caller = fn prompt ->
        :ets.update_counter(received_prompts, :count, {2, 1})
        :ets.insert(received_prompts, {:last_len, String.length(prompt)})
        {:ok, "{}"}
      end

      assert {:ok, _} =
               ThemeExtractor.extract(text, llm_caller: llm_caller, prompt_budget_chars: 5_000)

      [{:last_len, len}] = :ets.lookup(received_prompts, :last_len)
      [{:count, count}] = :ets.lookup(received_prompts, :count)

      assert count == 4
      # Each prompt embeds the excerpt + scaffold text, so length should be
      # at least the budget but not vastly larger.
      assert len >= 5_000
      assert len < 5_000 + 2_000

      :ets.delete(received_prompts)
    end
  end
end
