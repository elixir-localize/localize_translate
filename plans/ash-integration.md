# Ash integration

**Status:** draft, 2026-11-24

A proposal for using `Localize.Translate` with Ash resources, prompted by mishka_cms_core, an Ash application whose sites each choose their languages at runtime. Nothing here is built yet; a spike on three technical points comes first. The extension is a package of its own (decided 2026-11-24).

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

An Ash extension, `Localize.Translate.Ash`, in a package of its own, `localize_translate_ash`, which depends on `localize_translate` and `ash`. The core keeps no Ash or Spark dependency, and its CI and dependency tree stay as they are.

```elixir
defmodule MyApp.Media do
  use Ash.Resource,
    domain: MyApp.Runtime,
    data_layer: AshPostgres.DataLayer,
    extensions: [Localize.Translate.Ash]

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

The extension adds a `:translations` attribute of a new type, `Localize.Translate.Ash.Type.Translations`, stored as `jsonb` in the shape `Store.Embedded` already reads: `%{"es" => %{"name" => "Foto"}}`.

* **Runtime locales need a map.** A field per locale cannot be generated for languages a site adds after compilation.

* **One shape for Ecto and Ash.** The same column serves `translate/2,3`, `QueryBuilder` and the Ash calculations, and a table can move between the two.

* **The type validates what the map cannot.** Each locale key is validated with `Localize.validate_locale/1` and stored as its CLDR id (`"fr-CA"`); each inner key must be a translatable field; each value is cast with its base attribute's type and constraints, which the extension copies, so a translated name is held to the same 255 characters; an empty string is dropped, so the base value shows through. No key becomes an atom.

### Reading: calculations that work in the data layer

For each translated field the extension adds a calculation named `translated_<field>`, such as `translated_name`, of the base attribute's type, with an optional `:locale` argument. Its `expression/2` callback:

1. Takes the locale from the argument, then the query's `:locale` context, then `Localize.get_locale/0`.

2. Expands it to its CLDR parent chain with `Localize.Translate.Locale.expand/1` (`fr-CA` → `fr`).

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

* **`Localize.Translate.Ash.Changes.PutTranslation`** sets the fields given for one locale and keeps the others.

* **`Localize.Translate.Ash.Changes.RemoveTranslation`** removes one locale.

Each validates the locale against the `locales` option, when one is given, and implements `atomic/3` as a `jsonb` merge so it works in Ash's atomic updates.

### Runtime locales and the default locale

* **`locales`** is a list or a `{Module, function, args}` called with the changeset, and answers which locales a record may hold. Leaving it out allows any valid locale.

* **`default_locale`** names the language of the base attributes, as a locale or a `{Module, function, args}` called with the record or the query context. A site whose default language is French has French base columns, so a French request reads them directly and an English one reads the map. The extension passes it straight to the core's runtime `:default_locale` (below).

## Changes to the core library

These help Ecto users as much as Ash users, and the extension needs them:

* **Translate related records.** The core cannot name `Ash.Resource.Info` or `%Ash.NotLoaded{}` without depending on Ash, so `translate_assocs/2` asks the module, through a new reflection `__trans__(:associations)`, which fields hold related records, falling back to `__schema__/1` for an Ecto schema. It recurses only into values that are themselves translatable structs, so an unloaded marker of any data layer is left alone. The extension defines `__trans__(:associations)` from the resource's relationships.

* **A runtime default locale, for Ecto and Ash alike** (decided 2026-11-24). `:default_locale` also accepts a `{Module, function, args}`, called as `apply(module, function, [subject | args])`: with the struct for `translate/2,3`, and with `nil` for a query, since a query has no record. `translated/4` and `translated_as/4` take a `default_locale:` option for an application whose default depends on the record, such as the site's language. What makes it work is one invariant: **the container never holds an entry for the default locale**, because the base columns are that language. Writes enforce it: the Ecto `translations/1` macro already generates no embed for the default locale, and the Ash type and changes refuse it. Under the invariant `COALESCE(container->locale->>field, base)` is correct whatever the default is, so:

  * the static `QueryBuilder` path, which compares a literal locale with the default at compile time, emits the `COALESCE` instead of the base column when the default is a function;

  * the dynamic path passes the default to the `translate_field` database function as a runtime parameter (`^`) rather than a string fixed at compile time;

  * `translate/2,3` call the function once per call, not once per field.

  Changing a site's default language later leaves its base columns in the old language; moving the text is the application's migration, which the guide should say.

* **Stop raising on an invalid locale.** `Localize.Translate.Locale` raises "by design" on an invalid locale, so `translate/3` raises on input from a request. A library returns an error or falls back instead; `translate/3` should fall back to the base value and `translate!/3` raise.

## Testing

* Resources on `Ash.DataLayer.Ets` for the in-memory path, and on AshPostgres against the existing test database for SQL filters, sorts and atomic updates.

* For every record and locale chain in a fixture, the calculation loaded through SQL equals `translate/3` in memory.

* Tenant-scoped resources, so that `locales` and `default_locale` are exercised per tenant.

## Decisions

* 2026-11-24 — The extension is a separate package, `localize_translate_ash`, not an optional dependency of `localize_translate` (user). Because it keeps Ash and Spark out of the core's dependencies and CI. The core's related-records fix is therefore generic, through `__trans__(:associations)`.

* 2026-11-24 — A runtime `:default_locale` goes in the core, for Ecto as well as Ash (user). It rests on the invariant that the container holds no entry for the default locale.

* 2026-11-24 — Calculations are named `translated_<field>`, such as `translated_name` (user). Because it reads as English in filters, sorts and generated APIs.

## Tasks

* [ ] **Spike the open technical points** — whether AshPostgres compiles `||` between nullable strings to `COALESCE`, whether `get_path` with string keys reads a `jsonb` column as the type expects, and whether a Spark transformer can define `__trans__/1`. A day; it decides the expression shape before anything is built on it.

* [ ] **Core fixes** — relationships through `__trans__(:associations)`, a runtime `:default_locale` with the default-locale invariant in both `QueryBuilder` paths and the `translate_field` database function, and no raising on an invalid locale. Each lands and releases in `localize_translate` before the extension needs it.

* [ ] **The new package** — `localize_translate_ash` under `~/Development/localize/`, with the house CI matrix, pre-commit hook, `STATUS.md` and `CLAUDE.local.md`; the GitHub repository is the user's to create.

* [ ] **The type and the extension** — `Type.Translations`, the `translations` section, the attribute, `__trans__/1` and the calculations.

* [ ] **The write changes** — `PutTranslation` and `RemoveTranslation`, atomic.

* [ ] **A guide** — an Ash section in the guide, with the mishka shape (media name and description, media category, site name) as the example.
