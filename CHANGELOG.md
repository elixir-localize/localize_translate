# Changelog

## [v0.1.0] — 2026-05-13

Initial release. Provides embedded translations for `Ecto.Schema` modules — `use Localize.Translate` declares translatable fields, locales, and default locale; `Localize.Translate.translate/2,3` reads translations at runtime, and `Localize.Translate.QueryBuilder.translated/3` builds matching `Ecto.Query` fragments.

Built on [`:localize`](https://hex.pm/packages/localize) — atoms, strings, and `%Localize.LanguageTag{}` are accepted as locales in `:locales`, in `translate/N`, and in `QueryBuilder.translated/3`, all validated and normalised via `Localize.validate_locale/1`; fallback chains walk CLDR parent locales (filtered to the schema's supported locales for query building) and `translate/1,2` default to `Localize.get_locale/0`.
