%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: [
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
        {Credo.Check.Refactor.Nesting, [max_nesting: 4]}
      ],
      disabled: [
        {Credo.Check.Readability.AliasUsage, []},
        {Credo.Check.Readability.MultiAlias, []},
        {Credo.Check.Design.AliasUsage, []},
        {Credo.Check.Design.TaggedTupleSizing, []},
        {Credo.Check.Readability.Specs, []},
        {Credo.Check.Readability.WithCustomTaggedTuple, []},
        {Credo.Check.Refactor.ModuleDependencies, []},
        {Credo.Check.Refactor.FilterFilter, []},
        {Credo.Check.Consistency.MultiAliasImportRequireUse, []}
      ]
    }
  ]
}
