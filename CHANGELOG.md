# Changelog

## Localize Translate v0.1.0

Initial release. `localize_translate` derives from [trans](https://hex.pm/packages/trans) (and its CLDR-integrated fork `ex_cldr_trans`) but ships as a standalone library with no CLDR or backend dependency.

Schemas declare their translatable fields, configured locales, and default locale directly:

```elixir
use Localize.Translate,
  translates: [:title, :body],
  locales: [:en, :es, :fr],
  default_locale: :en
```

The library provides:

* Embedded translation storage in a single JSONB column per schema.

* Whole-struct and per-field translation with explicit fallback chains.

* `Ecto.Query` helpers (`translated/3`, `translated_as/3`) for filtering and selecting translated columns, including a Postgres `translate_field` function for runtime locale fallback.
