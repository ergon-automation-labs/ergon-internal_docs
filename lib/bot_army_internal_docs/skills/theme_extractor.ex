defmodule BotArmyInternalDocs.Skills.ThemeExtractor do
  @moduledoc """
  Extract a draft RPG theme from sourcebook text.

  ## Overview

  Takes raw extracted text from a sourcebook (typically via
  `BotArmyInternalDocs.Ingestion.Fetchers.LocalFile.fetch/1`) and runs a
  sequence of focused LLM prompts to produce a theme map shaped for
  `BotArmyRpg.Themes.Preset.theme/0` — the canonical structure the RPG
  bot's `ThemeStore` and narrator expect.

  ## Pipeline

    1. **Setting** — extract `setting`, `tone`, `mechanic` (1–2 sentences each).
    2. **Vocabulary** — extract substitutions for the ten standard action verbs.
    3. **Personas** — extract 4–6 NPC archetype descriptors (`title`, `demeanor`, `carries`).
    4. **Templates** — extract `scene_intro`, `combat_intro`, `rest_scene`, `victory`, `defeat`.
    5. **Rules** — leaves `action_types` populated and `resolution` empty; the
       d20 chassis is the safe default. A human edits this after review.

  ## LLM transport

  Each step calls `llm.prompt.submit` as a request/reply over NATS via
  `Gnat.request/4`. The transport is pluggable via the `:llm_caller` option,
  which makes the pipeline trivially stubbable in unit tests.

  ## Failure model

  An individual step that fails to return parsable JSON yields a placeholder
  for that field (`%{}`, `[]`, or `"TODO"` as appropriate) and surfaces a
  warning in the returned `:errors` list. The pipeline does **not** fail
  the whole extraction on a single bad step — partial output is still useful
  to a human reviewer.

  ## IP guardrails

  Prompts are explicit: paraphrase, do not quote. The pipeline does **not**
  verify the LLM obeyed; downstream operators should run a separate
  verbatim-overlap check before publishing a generated theme.
  """

  require Logger

  @action_verbs ~w(attack defend buff inspire inspect negotiate hack evade skill move)
  @persona_count 5
  @template_keys ~w(scene_intro combat_intro rest_scene victory defeat)
  @default_prompt_budget_chars 12_000
  @default_timeout_ms 60_000

  @type opts :: [
          llm_caller: (String.t() -> {:ok, String.t()} | {:error, term()}),
          prompt_budget_chars: pos_integer(),
          timeout_ms: pos_integer()
        ]

  @type result :: %{
          theme: map(),
          errors: [String.t()],
          warnings: [String.t()]
        }

  @doc """
  Extract a draft theme from raw sourcebook text.

  Returns `{:ok, %{theme: map, errors: [...], warnings: [...]}}`.

  ## Options

    * `:llm_caller` — `(prompt :: String.t() -> {:ok, response} | {:error, _})`.
      Defaults to `&default_llm_caller/1`, which submits via
      `llm.prompt.submit`.
    * `:prompt_budget_chars` — how much of the source text to inline per
      prompt. Default `#{@default_prompt_budget_chars}`.
    * `:timeout_ms` — per-LLM-call timeout. Default `#{@default_timeout_ms}`.
  """
  @spec extract(String.t(), opts) :: {:ok, result()}
  def extract(text, opts \\ []) when is_binary(text) do
    llm_caller = Keyword.get(opts, :llm_caller, &default_llm_caller/1)
    budget = Keyword.get(opts, :prompt_budget_chars, @default_prompt_budget_chars)

    excerpt = String.slice(text, 0, budget)

    {setting_fields, errors_a, warnings_a} = step_setting(excerpt, llm_caller)
    {vocabulary, errors_b, warnings_b} = step_vocabulary(excerpt, llm_caller)
    {personas, errors_c, warnings_c} = step_personas(excerpt, llm_caller)
    {templates, errors_d, warnings_d} = step_templates(excerpt, llm_caller)

    theme = %{
      "setting" => Map.get(setting_fields, "setting", "TODO"),
      "tone" => Map.get(setting_fields, "tone", "TODO"),
      "mechanic" => Map.get(setting_fields, "mechanic", "TODO"),
      "vocabulary" => vocabulary,
      "templates" => templates,
      "npc_personas" => personas,
      "rules" => %{"action_types" => @action_verbs}
    }

    {:ok,
     %{
       theme: theme,
       errors: errors_a ++ errors_b ++ errors_c ++ errors_d,
       warnings: warnings_a ++ warnings_b ++ warnings_c ++ warnings_d
     }}
  end

  defp step_setting(excerpt, llm_caller) do
    prompt = """
    You are summarizing a tabletop RPG sourcebook for use as a stylistic skin
    in another game. Paraphrase only — do not quote.

    From the sourcebook excerpt below, write a JSON object with three keys:

      "setting":  one short sentence naming the world/region in the author's voice.
      "tone":     one short sentence describing mood and prose register.
      "mechanic": one short sentence describing the core resolution mechanic.

    Return ONLY a single JSON object. No commentary, no markdown fences.

    Sourcebook excerpt:
    #{excerpt}
    """

    parse_json_step(llm_caller, prompt, "setting", %{}, &valid_setting_map?/1)
  end

  defp valid_setting_map?(m) when is_map(m) do
    Map.has_key?(m, "setting") and Map.has_key?(m, "tone") and Map.has_key?(m, "mechanic")
  end

  defp valid_setting_map?(_), do: false

  defp step_vocabulary(excerpt, llm_caller) do
    verb_list = Enum.map_join(@action_verbs, ", ", &"\"#{&1}\"")

    prompt = """
    You are extracting a vocabulary substitution table for a tabletop RPG
    stylistic skin. Paraphrase only — do not quote source text.

    For each of the following standard action verbs, propose a short
    setting-specific replacement word or phrase in the author's voice:
    #{verb_list}

    Return ONLY a single JSON object whose keys are exactly the verbs above
    and whose values are the proposed substitutions (each <= 6 words).
    No commentary, no markdown fences. If the source is unclear about a
    given verb, return "TODO" as that verb's value.

    Sourcebook excerpt:
    #{excerpt}
    """

    {map, errors, warnings} =
      parse_json_step(
        llm_caller,
        prompt,
        "vocabulary",
        %{},
        &is_map/1
      )

    filled = Map.new(@action_verbs, fn v -> {v, Map.get(map, v, "TODO")} end)
    {filled, errors, warnings}
  end

  defp step_personas(excerpt, llm_caller) do
    prompt = """
    You are extracting NPC/faction archetypes for a tabletop RPG stylistic
    skin. Paraphrase only — do not quote source text.

    From the sourcebook excerpt below, identify #{@persona_count} archetypes.
    For each, write a short JSON object with:
      "key":      a snake_case identifier (e.g. "court_warden"),
      "title":    the title shown to players (Title Case),
      "demeanor": one sentence describing voice, mood, and a single tell,
      "carries":  array of 2-3 short noun phrases describing iconic items.

    Return ONLY a single JSON array of #{@persona_count} such objects. No
    commentary, no markdown fences.

    Sourcebook excerpt:
    #{excerpt}
    """

    {raw, errors, warnings} = parse_json_step(llm_caller, prompt, "personas", [], &is_list/1)

    personas =
      raw
      |> Enum.filter(&valid_persona?/1)
      |> Enum.into(%{}, fn p ->
        {p["key"],
         %{
           "title" => p["title"],
           "demeanor" => p["demeanor"],
           "carries" => p["carries"],
           "bot_assignments" => []
         }}
      end)

    {personas, errors, warnings}
  end

  defp valid_persona?(%{"key" => k, "title" => t, "demeanor" => d, "carries" => c})
       when is_binary(k) and is_binary(t) and is_binary(d) and is_list(c),
       do: true

  defp valid_persona?(_), do: false

  defp step_templates(excerpt, llm_caller) do
    keys_list = Enum.map_join(@template_keys, ", ", &"\"#{&1}\"")

    prompt = """
    You are extracting short scene snippets for a tabletop RPG stylistic
    skin. Paraphrase only — do not quote source text.

    Write five short, atmospheric scene snippets in the author's voice
    (1-2 sentences each). The five keys are: #{keys_list}.

    Return ONLY a single JSON object whose keys are exactly the names above
    and whose values are the snippets. No commentary, no markdown fences.

    Sourcebook excerpt:
    #{excerpt}
    """

    {map, errors, warnings} = parse_json_step(llm_caller, prompt, "templates", %{}, &is_map/1)
    filled = Map.new(@template_keys, fn k -> {k, Map.get(map, k, "TODO")} end)
    {filled, errors, warnings}
  end

  defp parse_json_step(llm_caller, prompt, label, default, validator) do
    case llm_caller.(prompt) do
      {:ok, raw_response} ->
        case decode_json(raw_response) do
          {:ok, value} ->
            if validator.(value) do
              {value, [], []}
            else
              warning = "[ThemeExtractor:#{label}] LLM returned wrong shape; using default"
              Logger.warning(warning)
              {default, [], [warning]}
            end

          {:error, reason} ->
            error = "[ThemeExtractor:#{label}] could not parse LLM response: #{inspect(reason)}"
            Logger.error(error)
            {default, [error], []}
        end

      {:error, reason} ->
        error = "[ThemeExtractor:#{label}] LLM call failed: #{inspect(reason)}"
        Logger.error(error)
        {default, [error], []}
    end
  end

  defp decode_json(raw) when is_binary(raw) do
    raw
    |> strip_markdown_fences()
    |> Jason.decode()
  end

  defp decode_json(_), do: {:error, :not_a_string}

  defp strip_markdown_fences(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/m, "")
    |> String.replace(~r/```\s*$/m, "")
    |> String.trim()
  end

  defp default_llm_caller(prompt) do
    payload = %{
      "prompt" => prompt,
      "context" => %{
        "bot_id" => "internal_docs",
        "skill" => "theme_extractor"
      }
    }

    case Gnat.request(:gnat, "llm.prompt.submit", Jason.encode!(payload),
           receive_timeout: @default_timeout_ms
         ) do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "response" => response}} -> {:ok, response}
          {:ok, %{"ok" => false} = err} -> {:error, err}
          other -> {:error, {:unexpected_response, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
