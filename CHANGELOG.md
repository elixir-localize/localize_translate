# Changelog

## [v0.4.0] — 2026-11-24

Upgrading from an earlier release? See [Migrating to 0.4](https://hexdocs.pm/localize_translate/migrating_to_0_4.html), which covers the change from the `translate_field` database function to plain SQL and the database housekeeping.

### Added

* `:default_locale` also takes a `{module, function, arguments}` tuple, called with the struct (or `nil` for a query), for a default known only at runtime. `default_locale/1` resolves it, and `QueryBuilder.translated/4` and `translated_as/4` take a `:default_locale` option.

* `validate_translations/1` is a changeset validation that refuses translations for the record's own default locale, resolving a function default from the changed record, and, for a map container, invalid or unlisted locales.

* `reflection/1` generates the `__trans__/1` reflection with defaults for every key, for code that builds a translatable module without `use Localize.Translate`, such as an Ash extension.

* `locale_id/1` validates a locale and returns the CLDR locale id translations are keyed by, or an error, for code that stores or reads translations itself.

* `locale_chain/2` expands a locale or list into the CLDR fallback chain the reads walk, leaving out invalid locales, with `:supported` and `:default_locale` options, for code that builds its own lookups such as a data-layer calculation.

* `__trans__(:associations)` names the fields holding related records that `translate/2` also translates: an Ecto schema's associations and embeds by default, or a list of its own from a module that defines `__trans__/1` itself.

### Changed

* `translate/2,3` filter the locale chain by the schema's `:locales`, keeping the default locale, as queries do, so a stored locale the schema no longer lists is not read; `translate/2` filters each related record by its own `:locales`.

* `translate/3` returns the base value for a field that is not translatable, and `nil` for a field the struct lacks or a value that is not a struct, where it raised; `translate!/3` raises an `ArgumentError` for these instead of a `RuntimeError`. Both take a string field name without creating an atom.

* A `nil` translation counts as missing in `translate/2,3`, so a chain moves on to its next locale where it stopped at the base value, and `translate!/3` raises for it. Queries apply the same rule, including a `nil` base value at the default locale.

* `QueryBuilder` no longer needs the `translate_field` database function: every query reads the locale chain in plain SQL, the first four locales as direct `jsonb` expressions, so a `LanguageTag` query runs as fast as a hand-written one and about twenty-five times faster than the function. New applications skip `mix localize.translate.gen.translate_function`.

### Deprecated

* `mix localize.translate.gen.translate_function` warns when run and will be removed in a future release, since queries no longer call the `translate_field` function it creates.

### Fixed

* A query on a schema whose default locale is not in `:locales` dropped the default from the chain, so it read a later translation instead of the base column; the default locale is now kept.

* A language CLDR has no data for, such as `"tlh"`, resolves to the root `und` and is now left out of a chain and refused in `:locales`; every such language was read under the one `"und"` key.

* `translate!/3` loads translations before resolving, as `translate/3` does, so it works with `Store.SiblingResource`; it raised "translation doesn't exist" for every locale.

* `translate/1,2` return a value that is not a struct unchanged, where they raised `FunctionClauseError`.

* `Store.SiblingResource.load_translations/2` checks its options and the subject's key before querying and returns `{:error, %ArgumentError{}}` for each problem, instead of raising and rescuing; only the repo call is rescued, returning the database error.

* `translatable?/2` no longer creates an atom from a string field name, and returns `false` instead of raising for a module that does not use `Localize.Translate` or for arguments that are not a module and a field name.

* `Store.Embedded` no longer raises on a container or locale entry that is not a map, which a `jsonb` column can hold: reads are a miss and `put_translation/5` returns `{:error, %ArgumentError{}}`. A write of an unknown locale or field to a struct container is refused instead of adding a stray key.

* A runtime-locale query works with any binding name and on joined schemas; it guessed the table alias from the binding name, so `from b in Book` (alias `a0`) failed. A literal locale is now expanded and validated as a runtime one is, so `:"es-419"` reads `:es`.

* `QueryBuilder.translated/3` with a literal chain such as `[:it, :es]` returned the base column when the first locale had no translation; it now moves on, as a runtime chain and `translate/3` do.

* A runtime-locale query on a schema with no `:default_locale` no longer treats `:en` as the default.

* `translate/2` no longer raises on a struct that is not an Ecto schema, or on a related value that is a plain map; it translates only related values that are themselves translatable structs.

* `translate/2,3` and `QueryBuilder.translated/3` no longer raise on an invalid locale, `nil` included: it is left out of the fallback chain, so the base value is returned. `translate!/3` still raises `Localize.InvalidLocaleError`.

## [v0.3.0] — 2026-11-24

### Added

* `translations/3` takes `fields_module:`, a per-locale embedded schema of your own used in place of the generated `Fields`, so state such as a translator or an update time can be kept beside each locale's translations. It must define every translatable field as a `:string`, which is checked when the parent schema compiles.

### Changed

* `translations/3` raises an `ArgumentError` at compile time for an option it does not know, where it ignored it.

### Fixed

* `Localize.Translate.JSON` encodes `Date`, `Time`, `NaiveDateTime` and `DateTime` as ISO 8601 strings and a `Decimal` as its text, so an embedded schema with such a field can be stored. It raised on them.

## [v0.2.0] — 2026-08-01

The store behaviour is new public API and its first consumer — the Ash integration — has not yet written an adapter against it. The package stays on a 0.x line until that shape is agreed, so it can change without a major bump.

### Added

* `Localize.Translate.Store` — a behaviour for translation storage, so translations need not live on the subject. It is subject-and-field shaped: a store receives the whole subject rather than an extracted key, so a CLDR fallback chain resolves in one pass.

* `Localize.Translate.Store.Embedded` — the default store, implementing the container-map storage this library has always used. Existing schemas keep working unchanged.

* `Localize.Translate.Store.SiblingResource` — a store keeping translations in a sibling table, one row per `(subject, locale)`. For per-translation workflow state, per-locale permissions, row-level translation history, or concurrent editing across locales.

* A schema selects its store with `use Localize.Translate, store: MyStore` or `store: {MyStore, options}`.

### Changed

* Requires `localize ~> 1.0`. The previous requirement of `~> 0.32` excluded it.

* Test database connection settings read the standard `PG*` environment variables, so the same configuration works on CI and on a developer machine.

### Fixed

* `Mix.Tasks.Localize.Translate.Gen.TranslateFunction.format_string!/1` returns a binary rather than iodata, and no longer carries a `@dialyzer {:no_return, ...}` annotation that claimed it never returns.

## [v0.1.0] — 2026-05-13

Initial release. Provides embedded translations for `Ecto.Schema` modules — `use Localize.Translate` declares translatable fields, locales, and default locale; `Localize.Translate.translate/2,3` reads translations at runtime, and `Localize.Translate.QueryBuilder.translated/3` builds matching `Ecto.Query` fragments.

Built on [`:localize`](https://hex.pm/packages/localize) — atoms, strings, and `%Localize.LanguageTag{}` are accepted as locales in `:locales`, in `translate/N`, and in `QueryBuilder.translated/3`, all validated and normalised via `Localize.validate_locale/1`; fallback chains walk CLDR parent locales (filtered to the schema's supported locales for query building) and `translate/1,2` default to `Localize.get_locale/0`.
