# Localize Translate

`localize_translate` keeps the translations of an Ecto schema's fields in the schema itself, in one JSON column, and reads and queries them with CLDR locale fallback. It removes the need for a translation table beside every translatable table.

## Features

* **Embedded translations** — each translatable schema carries its translations in one `jsonb` column, so reading a record with its translations needs no join.

* **Locale fallback** — `Localize.Translate.translate/2,3` takes a locale or a chain of them, and follows CLDR parent locales (`en-AU` → `en-001` → `en`) before falling back to the base column.

* **Translated queries** — `Localize.Translate.QueryBuilder` provides `Ecto.Query` macros that filter and select translated values in SQL, with the same fallback.

* **Per-locale state** — `translations/3` takes a per-locale schema of your own with `:fields_module`, to keep a translator, a timestamp or a review flag beside each locale's translations.

* **Storage backends** — the `Localize.Translate.Store` behaviour, with an embedded store (the default) and a sibling-table store, one row per subject and locale.

## Supported Elixir and OTP versions

`localize_translate` requires **Elixir 1.17** or later and **OTP 26** or later.

## Installation

Add `localize_translate` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize_translate, "~> 0.3"}
  ]
end
```

### Optional requirements

With Ecto SQL and Postgrex in your application, `Localize.Translate.QueryBuilder` generates database queries on translated data. The runtime `Localize.Translate.translate/2,3` functions work without them.

* [Ecto SQL](https://hex.pm/packages/ecto_sql) 3.0 or later.

* [PostgreSQL](https://hex.pm/packages/postgrex) 9.4 or later, since `Localize.Translate` uses the `jsonb` datatype.

## Why Localize Translate?

The traditional approach to content internationalization uses an additional table for each translatable schema, which holds only that schema's translations: a `posts` table and a `posts_translations` table, for example.

This approach has a few disadvantages:

* It complicates the database schema, because it creates extra tables that are coupled to the main ones.

* It makes migrations and schemas more complicated, since the two tables must always be kept in sync.

* It requires constant joins to filter or fetch records along with their translations.

`Localize.Translate` relies instead on the support modern databases have for unstructured datatypes. Each translatable schema has an extra column that contains all of its translations, which drastically reduces the number of joins needed to filter or fetch records.

## Quick start

Imagine that we have an `Article` schema that we want to translate:

```elixir
defmodule MyApp.Article do
  use Ecto.Schema

  schema "articles" do
    field :title, :string
    field :body, :string
  end
end
```

### Add a JSON column

The first step is to add a JSON column to the table to store the translations in.

```elixir
defmodule MyApp.Repo.Migrations.AddTranslationsToArticles do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      add :translations, :map
    end
  end
end
```

### Generate the database function migration

`localize_translate` defines a Postgres function that translates a field in the database. A mix task generates the migration that defines it.

```bash
mix localize.translate.gen.translate_function
```

### Run the migrations

Migrate the database to add the translations column and define the database function.

```bash
mix ecto.migrate
```

### Add translations to the schema

With the new column in place, declare the translatable fields and the configured locales in the schema:

```elixir
defmodule MyApp.Article do
  use Ecto.Schema
  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "articles" do
    field :title, :string
    field :body, :string
    # use the 'translations' macro to set up a map-field with a set of nested
    # structs to handle translation values for each configured locale and each
    # translatable field
    translations :translations
  end
end
```

The `:default_locale` keeps its values in the main schema columns; only the other locales get embedded translation fields.

### Cast translations

`localize_translate` generates a simple default changeset for each locale's translation fields. It looks like this:

```elixir
def changeset(fields, params) do
  fields
  |> cast(params, list_of_translatable_fields)
  |> validate_required(list_of_translatable_fields)
end
```

The schema's own changeset casts the translations field, and names the locales that take input:

```elixir
  def changeset(article, params \\ %{}) do
    article
    |> cast(params, [:title, :body])
    |> cast_embed(:translations, with: &translations_changeset/2)
    |> validate_required([:title, :body])
  end

  defp translations_changeset(translations, params) do
    translations
    |> cast(params, [])
    |> cast_embed(:es)
    |> cast_embed(:fr)
  end
end
```

### Read and query translations

After the schema is configured, use `Localize.Translate.translate/2,3` to fetch translations and `Localize.Translate.QueryBuilder` to query them:

```elixir
# Translate a single field, with fallback chain
Localize.Translate.translate(article, :title, [:de, :es])

# Translate the whole struct (and its embeds/associations) into Spanish
Localize.Translate.translate(article, :es)

# Filter on a translation in a query
from a in Article,
  where: translated(Article, a.title, :fr) == "Elixir"
```

Locales are validated with `Localize.validate_locale/1`, so atoms (`:en`), strings (`"en"`) and `Localize.LanguageTag` structs are all accepted. Fallback chains follow CLDR parent locales automatically — for example, `Localize.Translate.translate(article, :title, Localize.LanguageTag.new!("en-AU"))` walks `:"en-AU"` → `:"en-001"` → `:en`.

## Per-locale state

To keep state beside each locale's translations — who translated it, when, whether it was machine-translated — give `translations` a per-locale schema of your own with `:fields_module`. The `Translations` schema is still generated, and each locale embeds your schema instead of the generated `Fields`.

```elixir
defmodule MyApp.Article.TranslationFields do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
    field :body, :string
    field :translated_by, :string
    field :machine_translated, :boolean, default: false
    field :translated_at, :utc_datetime
  end

  def changeset(fields, params) do
    fields
    |> cast(params, [:title, :body, :translated_by, :machine_translated, :translated_at])
    |> validate_required([:title])
  end
end

defmodule MyApp.Article do
  use Ecto.Schema
  use Localize.Translate, translates: [:title, :body], locales: [:en, :es, :fr], default_locale: :en

  schema "articles" do
    field :title, :string
    field :body, :string
    translations :translations, Translations, fields_module: MyApp.Article.TranslationFields
  end
end
```

The schema must define every field in `:translates` as a `:string`, which is checked when `MyApp.Article` compiles, and it must be defined before `MyApp.Article`, not nested inside it. `Localize.Translate.translate/3` and the query builder read only the translatable fields. A query on a whole locale, `translated(Article, a, :es)`, reads the locale's whole object, so a locale that holds only state is not `NULL`.

## Storage backends

Translations are read through a store, declared per schema. `Localize.Translate.Store.Embedded` is the default and needs no configuration — it keeps translations in a container field on the schema, which is the model described above.

`Localize.Translate.Store.SiblingResource` keeps them in a sibling table instead, one row per `(subject, locale)`. That is the model this package exists to avoid, so reach for it only when you need something the embedded model cannot express: per-translation workflow state, per-locale permissions, row-level translation history, or concurrent editing across locales without contending on one column.

Both implement `Localize.Translate.Store`, so `translate/2,3` behaves identically either way, and a custom store — ETS, a file, a translation service — only has to implement that behaviour.

## Documentation

* **[Building translatable database systems](https://hexdocs.pm/localize_translate/translatable_database_systems.html)** — the design choices and the step-by-step setup, from the migration to forms, queries and tests.

* **[Changelog](https://hexdocs.pm/localize_translate/changelog.html)** — what changed in each release.

The full documentation is on [HexDocs](https://hexdocs.pm/localize_translate).

## Attribution

`localize_translate` derives from [trans](https://github.com/crbelaus/trans) by [@crbelaus](https://github.com/crbelaus) and its CLDR-integrated fork [ex_cldr_trans](https://github.com/elixir-cldr/cldr_trans). It is the continuation of that work within the `localize` ecosystem, built on [`:localize`](https://hex.pm/packages/localize) for CLDR-aware locale validation and parent-chain fallback.

## License

`localize_translate` is released under the Apache License 2.0; see [LICENSE.md](https://github.com/elixir-localize/localize_translate/blob/v0.3.0/LICENSE.md).
