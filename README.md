# Localize Translate

## Installation

The package can be installed by adding `localize_translate` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize_translate, "~> 0.2"}
  ]
end
```

Documentation can be found at [https://hexdocs.pm/localize_translate](https://hexdocs.pm/localize_translate).

## Attribution

`localize_translate` derives from [trans](https://github.com/crbelaus/trans) by [@crbelaus](https://github.com/crbelaus) and its CLDR-integrated fork [ex_cldr_trans](https://github.com/elixir-cldr/cldr_trans). It is the continuation of that work within the `localize` ecosystem, built on [`:localize`](https://hex.pm/packages/localize) for CLDR-aware locale validation and parent-chain fallback.

### Introduction

`localize_translate` provides a way to manage and query translations embedded into schemas and removes the necessity of maintaining extra tables only for translation storage.

## Optional Requirements

Having Ecto SQL and Postgrex in your application will allow you to use the `Localize.Translate.QueryBuilder` component to generate database queries based on translated data. The runtime `Localize.Translate.translate/2,3` functions work without those dependencies.

- [Ecto SQL](https://hex.pm/packages/ecto_sql) 3.0 or higher
- [PostgreSQL](https://hex.pm/packages/postgrex) 9.4 or higher (since `Localize.Translate` leverages the JSONB datatype)

## Why Localize Translate?

The traditional approach to content internationalization consists on using an additional table for each translatable schema. This table works only as a storage for the original schema translations. For example, we may have a `posts` and a `posts_translations` tables.

This approach has a few disadvantages:

- It complicates the database schema because it creates extra tables that are coupled to the "main" ones.
- It makes migrations and schemas more complicated, since we always have to keep the two tables in sync.
- It requires constant JOINs in order to filter or fetch records along with their translations.

The approach used by `Localize.Translate` is based on modern RDBMSs support for unstructured datatypes. Instead of storing the translations in a different table, each translatable schema has an extra column that contains all of its translations. This approach drastically reduces the number of required JOINs when filtering or fetching records.

## Storage backends

Translations are read through a store, declared per schema. `Localize.Translate.Store.Embedded` is the default and needs no configuration — it keeps translations in a container field on the schema, which is the model described above.

`Localize.Translate.Store.SiblingResource` keeps them in a sibling table instead, one row per `(subject, locale)`. That is the model this package exists to avoid, so reach for it only when you need something the embedded model cannot express: per-translation workflow state, per-locale permissions, row-level translation history, or concurrent editing across locales without contending on one column.

Both implement `Localize.Translate.Store`, so `translate/2,3` behaves identically either way, and a custom store — ETS, a file, a translation service — only has to implement that behaviour.

`Localize.Translate` is lightweight and modularized. The `Localize.Translate` module provides the `use` macro for declaring translatable schemas, the runtime `translate/2,3` functions, and field reflection. `Localize.Translate.QueryBuilder` provides the `Ecto.Query` macros for filtering and selecting translated values in SQL.

## Quickstart

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

The first step would be to add a new JSON column to the table so we can store the translations in it.

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

### Generate database function migration

`localize_translate` defines a Postgres database function to support in-db field translation. A migration task is provided to generate the migration required to define this function.

```elixir
% MIX_ENV=test mix localize.translate.gen.translate_function
* creating priv/repo/migrations
* creating priv/repo/migrations/20220307212312_localize_translate_gen_translate_function.exs
```

### Run migrations

Migrate the database to add the translations column and define the database function.

```elixir
% mix ecto.migrate
```

### Add translations to schema

Once we have the new database column, update the Article schema to declare translatable fields and the configured locales:

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

The `:default_locale` field stores its values in the main schema columns; only the other locales get embedded translation fields.

### Casting translations

`localize_translate` will generate a simple default changeset for the translations field. It looks like this:

```elixir
def changeset(fields, params) do
  fields
  |> cast(params, list_of_translatable_fields)
  |> validate_required(list_of_translatable_fields)
end
```

That may not be flexible enough for all requirements. A custom changeset can be defined for the translations field:

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

### Query Building

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

Locales are validated via `Localize.validate_locale/1`, so atoms (`:en`), strings (`"en"`), and `Localize.LanguageTag` structs are all accepted. Fallback chains follow CLDR parent locales automatically — for example, `Localize.Translate.translate(article, :title, Localize.LanguageTag.new!("en-AU"))` walks `:"en-AU"` → `:"en-001"` → `:en`.
