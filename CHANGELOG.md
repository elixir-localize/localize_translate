# Changelog

## [v0.1.0] — 2026-05-13

Initial release. Provides embedded translations for `Ecto.Schema` modules — `use Localize.Translate` declares translatable fields, locales, and default locale; `Localize.Translate.translate/2,3` reads translations at runtime, and `Localize.Translate.QueryBuilder.translated/3` builds matching `Ecto.Query` fragments.
