# Ash integration

**Status:** draft, 2026-11-24

A proposal for using `Localize.Translate` with Ash resources, prompted by mishka_cms_core, an Ash application whose sites each choose their languages at runtime. The spike is done and confirms the design (see "Spike findings"); the core fixes come next. The extension is a package of its own (decided 2026-11-24).

## The problem

`Localize.Translate` is written for Ecto, and an Ash resource is only partly Ecto. What works today and what does not, checked against Ash 3.38 and AshPostgres 2.16:

* **Reading works by accident.** An Ash resource defines a real Ecto schema for its attributes, so `use Localize.Translate` in a resource with a `:map` attribute named `:translations` gives it `__trans__/1`, and `translate/2,3` read the attribute through `Store.Embedded`, which takes the string keys a `jsonb` column loads with.

* **Related records are not translated.** Ash relationships are not Ecto associations, so `translate_assocs/2` finds none in `__schema__(:associations)` and leaves loaded relationships untranslated. Nothing fails; the related records simply stay in the base language.

* **Writing is unvalidated.** The `translations/1` macro builds an Ecto embedded schema, which an Ash resource cannot use. A plain `:map` attribute accepts any keys and any values: an invalid locale, a field that is not translatable, a 10,000-character name where the base attribute allows 255.

* **Querying is Ecto-only.** `QueryBuilder.translated/3` emits `Ecto.Query` fragments. Ash filters and sorts are Ash expressions, so a resource cannot filter or sort by a translated value.

* **Locales are fixed at compile time.** `:locales` and `:default_locale` are compile-time options. A CMS site picks its languages, and the language of its base columns, at runtime, per tenant.

## Prior art

`ash_translation` (0.2.6 on hex, about 10,000 downloads) is an Ash extension for the same job. It generates an embedded `Translations` resource with one attribute per locale from a compile-time `locales` list, translates in memory with no fallback beyond the base value, and has no calculation, so a translated value cannot be filtered or sorted in the data layer. It is built on `ex_cldr` and derives `Jason.Encoder`. Its storage model is the one runtime locales rule out, so contributing to it would mean replacing it; this proposal builds on `Localize.Translate` instead.

## Proposal

An Ash extension, `AshLocalizeTranslate`, in a package of its own, `ash_localize_translate`, which depends on `localize_translate` and `ash`. The core keeps no Ash or Spark dependency, and its CI and dependency tree stay as they are.

```elixir
defmodule MyApp.Media do
  use Ash.Resource,
    domain: MyApp.Runtime,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshLocalizeTranslate]

  translations do
    translates [:name, :description]
    default_locale {MyApp.Sites, :default_locale, []}
    locales {MyApp.Sites, :locales, []}
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, constraints: [max_length: 255]
    attribute :description, :string, constraints: [max_length: 1000]
  end
end
```

### Storage: one map attribute, not a resource per locale

The extension adds a `:translations` attribute of a new type, `AshLocalizeTranslate.Type.Translations`, stored as `jsonb` in the shape `Store.Embedded` already reads: `%{"es" => %{"name" => "Foto"}}`.

* **Runtime locales need a map.** A field per locale cannot be generated for languages a site adds after compilation.

* **One shape for Ecto and Ash.** The same column serves `translate/2,3`, `QueryBuilder` and the Ash calculations, and a table can move between the two.

* **The type validates what the map cannot.** Each locale key is validated with `Localize.validate_locale/1` and stored as its CLDR id (`"fr-CA"`); each inner key must be a translatable field; each value is cast with its base attribute's type and constraints, which the extension copies, so a translated name is held to the same 255 characters; an empty string is dropped, so the base value shows through. No key becomes an atom.

### Reading: calculations that work in the data layer

For each translated field the extension adds a calculation named `translated_<field>`, such as `translated_name`, of the base attribute's type, with an optional `:locale` argument. Its `expression/2` callback:

1. Takes the locale from the argument, then the query's `:locale` context, then `Localize.get_locale/0`.

2. Expands it to its CLDR parent chain with `Localize.Translate.locale_chain/2` (`fr-CA` → `fr`), public since 0.4.0 for this purpose.

3. Returns an expression that reads each locale in turn and falls back to the base attribute, of the form `type(translations["fr-CA"]["name"], :string) || type(translations["fr"]["name"], :string) || name`.

Because it is an expression, AshPostgres runs it in SQL and the ETS and embedded data layers run it in memory. It can be loaded, filtered and sorted, and AshJsonApi and AshGraphql expose it:

```elixir
MyApp.Media
|> Ash.Query.filter(translated_name(locale: "fr") == "Photo")
|> Ash.Query.sort(translated_name: :asc)
|> Ash.Query.load(:translated_name)
|> Ash.read!(tenant: site_id)
```

`Localize.Translate.translate/2,3` keep working on a loaded record, in memory, for code that already has one.

### Writing: changes that merge one locale

A whole-map update replaces every locale, so the extension provides changes that touch one locale at a time:

* **`AshLocalizeTranslate.Changes.PutTranslation`** sets the fields given for one locale and keeps the others.

* **`AshLocalizeTranslate.Changes.RemoveTranslation`** removes one locale.

Each validates the locale against the `locales` option, when one is given, and implements `atomic/3` as a `jsonb` merge so it works in Ash's atomic updates.

### Runtime locales and the default locale

* **`locales`** is a list or a `{Module, function, args}` called with the changeset, and answers which locales a record may hold. Leaving it out allows any valid locale.

* **`default_locale`** names the language of the base attributes, as a locale or a `{Module, function, args}` called with the record or the query context. A site whose default language is French has French base columns, so a French request reads them directly and an English one reads the map. The extension passes it straight to the core's runtime `:default_locale` (below).

## Changes to the core library

These help Ecto users as much as Ash users, and the extension needs them:

* **Translate related records.** The core cannot name `Ash.Resource.Info` or `%Ash.NotLoaded{}` without depending on Ash, so `translate_assocs/2` asks the module, through a new reflection `__trans__(:associations)`, which fields hold related records, falling back to `__schema__/1` for an Ecto schema. It recurses only into values that are themselves translatable structs, so an unloaded marker of any data layer is left alone. The extension defines `__trans__(:associations)` from the resource's relationships.

* **A runtime default locale, for Ecto and Ash alike** (decided 2026-11-24, built 2026-11-24). `:default_locale` also accepts a `{Module, function, args}`, called as `apply(module, function, [subject | args])`: with the struct for `translate/2,3`, and with `nil` for a query, since a query has no record. `Localize.Translate.default_locale/1` resolves it to a CLDR locale id or `nil`, and `translated/4` and `translated_as/4` take a `default_locale:` option for a default that depends on the tenant, such as the site's language. Every path compares each locale in the chain with the resolved default: `translate/2,3` once per struct, and every `QueryBuilder` query through a subquery over the locale array that takes the default as a parameter (built 2026-11-24; the `translate_field` database function is no longer used). Only when no default resolves does correctness rest on the invariant that **the container holds no entry for the default locale**; the Ash type and changes enforce it, and the guide asks Ecto users to, since `translations/1` cannot leave out an embed for a default it does not know at compile time.

  Changing a site's default language later leaves its base columns in the old language; moving the text is the application's migration, which the guide says.

* **Stop raising on an invalid locale.** `Localize.Translate.Locale` raises "by design" on an invalid locale, so `translate/3` raises on input from a request. A library returns an error or falls back instead; `translate/3` should fall back to the base value and `translate!/3` raise.

## Testing

* Resources on `Ash.DataLayer.Ets` for the in-memory path, and on AshPostgres against the existing test database for SQL filters, sorts and atomic updates.

* For every record and locale chain in a fixture, the calculation loaded through SQL equals `translate/3` in memory.

* Tenant-scoped resources, so that `locales` and `default_locale` are exercised per tenant.

## Spike findings

Run 2026-11-24 against Ash 3.38.0, AshPostgres 2.16 and Spark 2.7.10, in a throwaway project with a hand-written calculation module and a minimal extension.

* **`||` compiles to `COALESCE`.** A `fr-CA` chain becomes nested `coalesce(jsonb_extract_path_text(translations, $1, $2), coalesce(…, name))`. Load, filter and sort all run in SQL, and the locale and field names are bound parameters, not interpolated text.

* **String-keyed `get_path` reads `jsonb` correctly.** `get_path(^ref(:translations), ^["fr", "name"])` compiles to `jsonb_extract_path_text` with string parameters, and `type(…, :string)` casts the result. Ash 3.38 requires `ref` to be pinned inside `expr` (`^ref(field)`).

* **A transformer can build everything.** `Ash.Resource.Builder.add_new_attribute/4` and `add_new_calculation/5` add the `:translations` attribute and one `translated_<field>` calculation per field, and `Spark.Dsl.Transformer.eval/3` defines `__trans__/1`. The core's `translate/2,3` then work on an Ash record unchanged. The spike ordered its transformer with `before?(_) -> true`; the extension must name the Ash transformers it precedes. The core's `@after_compile` field and container checks do not run this way, so the extension needs a verifier that does the same.

* **Memory and SQL agree.** On `Ash.DataLayer.Ets` the same expression gave the same load, filter and sort results as AshPostgres for six fixtures, including a missing locale, a `null` value, an empty string and a number.

* **The query's locale context is reachable.** The calculation reads it as `context.source_context[:locale]`, after the argument and before `Localize.get_locale/0`. `Ash.Query.set_context(query, %{locale: "fr"})` drives load and filter.

* **The write side must clean values.** Both layers return an empty string rather than falling back, and return the number `42` as `"42"`. So the type must drop empty strings and cast each value with its base attribute's type, as the proposal says; the read expression can stay simple.

* **An invalid locale raises inside the calculation**, since `Localize.Translate.Locale.expand/1` raises. This is the core fix already listed, and the calculation must fall back to the base attribute instead.

## Decisions

* 2026-11-24 — The package is `ash_localize_translate`, with the root module `AshLocalizeTranslate` (user). Its project exists as a sibling checkout; work on it starts only when the `localize_translate` fixes are finished.

* 2026-11-24 — `QueryBuilder` walks the chain with a plain SQL subquery, not the `translate_field` function (user). Because the function took the whole row by a guessed table alias, and a subquery reads columns through Ecto and needs no migration.

* 2026-11-24 — A `nil` field in a translation moves on to the next locale everywhere (user). Because SQL queries, the Ash calculation and ETS already do, so only `translate/3` changes.

* 2026-11-24 — The extension is a separate package, `ash_localize_translate`, not an optional dependency of `localize_translate` (user). Because it keeps Ash and Spark out of the core's dependencies and CI. The core's related-records fix is therefore generic, through `__trans__(:associations)`.

* 2026-11-24 — A runtime `:default_locale` goes in the core, for Ecto as well as Ash (user). Every path compares with the resolved default; only when none resolves does it rest on the invariant that the container holds no entry for the default locale.

* 2026-11-24 — Calculations are named `translated_<field>`, such as `translated_name` (user). Because it reads as English in filters, sorts and generated APIs.

## Tasks

* [x] **Spike the open technical points** — all three confirmed, plus ETS parity and the query locale context; see "Spike findings". 2026-11-24.

* [x] **Core fixes** — relationships through `__trans__(:associations)`, a runtime `:default_locale` with the default-locale invariant in both `QueryBuilder` paths and the `translate_field` database function, and no raising on an invalid locale. Each lands and releases in `localize_translate` before the extension needs it. No raising on an invalid locale is done (8f95198): `Locale.expand/2` returns `{:ok, chain}` or `{:error, exception}`, and `Locale.expand_valid/2` leaves invalid locales out, which the calculation can use. `__trans__(:associations)` is done (befe2c2); the extension defines it from the resource's relationships. The runtime default locale is done (uncommitted, 2026-11-24), and fixed a literal-chain bug on the way. All three release together in 0.4.0.

* [ ] **The new package** — `ash_localize_translate` under `~/Development/localize/` (created by the user as a `mix new` project, 2026-11-24), with the house CI matrix, pre-commit hook, `STATUS.md` and `CLAUDE.local.md`.

* [ ] **The type and the extension** — `Type.Translations`, the `translations` section, the attribute, `__trans__/1` and the calculations.

* [ ] **The write changes** — `PutTranslation` and `RemoveTranslation`, atomic.

* [ ] **A guide** — an Ash section in the guide, with the mishka shape (media name and description, media category, site name) as the example.
