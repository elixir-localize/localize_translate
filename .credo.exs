# Credo configuration for Localize.Translate.
#
# Mirrors the Localize policy: strict, with `Design.AliasUsage` disabled.
# Schema and query-builder code fully qualifies many calls because module
# names such as `Localize.Translate.QueryBuilder` and `Ecto.Query` read
# more clearly at the call site than an alias, and because trailing
# segments such as `Locale`, `Query` and `JSON` shadow other modules when
# aliased. Alias submodules opportunistically where the trailing segment
# does not clash, never as a bulk conversion.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"]
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
