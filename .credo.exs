%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: [
        {Credo.Check.Warning.Dbg, []},
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
        {Credo.Check.Refactor.Nesting, [max_nesting: 4]}
      ]
    },
    %{
      name: "ignore-refactors",
      files: %{
        included: [
          "lib/bot_army_internal_docs/graph",
          "lib/bot_army_internal_docs/graph_migrations",
          "lib/bot_army_internal_docs/graph_migrator.ex"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: [
        {Credo.Check.Warning.Dbg, []}
      ]
    }
  ]
}
