# Changelog

## [v1.0.0] — 2026-08-01

### Changed

* Requires `localize ~> 1.0`. The previous requirement of `~> 0.32` excluded it.

* Test database connection settings read the standard `PG*` environment variables, so the same configuration works on CI and on a developer machine.

### Fixed

* `Mix.Tasks.Localize.Translate.Gen.TranslateFunction.format_string!/1` returns a binary rather than iodata, and no longer carries a `@dialyzer {:no_return, ...}` annotation that claimed it never returns.

## [v0.1.0] — 2026-05-13

Initial release. Provides embedded translations for `Ecto.Schema` modules — `use Localize.Translate` declares translatable fields, locales, and default locale; `Localize.Translate.translate/2,3` reads translations at runtime, and `Localize.Translate.QueryBuilder.translated/3` builds matching `Ecto.Query` fragments.

Built on [`:localize`](https://hex.pm/packages/localize) — atoms, strings, and `%Localize.LanguageTag{}` are accepted as locales in `:locales`, in `translate/N`, and in `QueryBuilder.translated/3`, all validated and normalised via `Localize.validate_locale/1`; fallback chains walk CLDR parent locales (filtered to the schema's supported locales for query building) and `translate/1,2` default to `Localize.get_locale/0`.
