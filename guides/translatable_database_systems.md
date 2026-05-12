# Building Translatable Database Systems

This guide walks through the design choices and step-by-step setup involved in adding multilingual content to an `Ecto`-backed application using `Localize.Translate`. By the end you will have a working schema where every translatable record carries its own translations in a single JSONB column, queryable from SQL with locale fallback, and editable through ordinary Phoenix forms.

## Why embedded translations?

The traditional pattern for multilingual content uses a side table per translatable schema:

```
articles                    articles_translations
 id  title  body             id  article_id  locale  title  body
```

Every read joins both tables, every write touches both, and every new translatable schema doubles the number of tables, foreign keys, and migrations to keep in sync. The translation table is also semantically empty — it exists only because the database doesn't know how to store a dictionary in a column.

Modern PostgreSQL handles JSONB natively, so an alternative is to keep the translations on the original row:

```
articles
 id  title           body            translations
                                     {"es": {"title": "...", "body": "..."},
                                      "fr": {"title": "...", "body": "..."}}
```

The base columns hold the canonical (default-locale) values; the JSONB column holds everything else. No joins, no separate migrations, no extra indexes for translation lookups. The shape is also self-describing — translations travel with the row.

`Localize.Translate` gives this pattern a name and a small library: a `use` macro that declares which fields are translatable, helpers for reading translated values with fallback, and `Ecto.Query` macros that compile down to SQL with the right `COALESCE` / JSONB-path logic.

## When this pattern fits and when it doesn't

**It fits when:**

* Translations are *editorial* — a small team curates the content for each locale.

* Records are mostly fetched whole. The application typically reads the article, then renders it.

* You want translations to version, soft-delete, and replicate alongside the parent row.

* You want a small number of related schemas — not a translation-driven CMS with hundreds of tables.

**It doesn't fit when:**

* Translations are *crowdsourced* and version-controlled independently. A side table with audit history is more honest.

* You need to query *across* translations: "find every article that mentions X in any locale". Possible with JSONB but cumbersome; a search index is usually a better answer.

* Translations are extremely large — a multi-MB localised body per locale will inflate the row and the table's TOAST overhead.

If the fit is partial, you can mix the two: small fields (title, slug, summary) embedded; long-form body in a side table.

## Step 1 — Decide on locales and a default

Before writing any code, pin down two things:

1. **Which locales will you support?** A fixed list of atoms: `[:en, :es, :fr, :"pt-BR"]`. Locale tags follow [BCP 47](https://www.rfc-editor.org/rfc/bcp/bcp47.txt) — language, optional script, optional region.

2. **Which locale is the default?** The default locale's content lives in the *base columns* of the table, not the JSON. This is significant: the default is the canonical value, the fallback target, and the row's identity in most situations.

A common choice is `:en` as the default. If your team works in another language, pick that — the default-locale content is what writers will edit most often, so it should match their working language.

## Step 2 — Database setup

Each translatable table needs one extra column — `:map` in Ecto, which becomes `jsonb` on PostgreSQL.

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

If you're starting from a new table, add the column inline:

```elixir
def change do
  create table(:articles) do
    add :title, :string
    add :body, :text
    add :translations, :map
    timestamps()
  end
end
```

### Generate the `translate_field` SQL function

For query-time locale fallback (covered later), `Localize.Translate.QueryBuilder` calls a PostgreSQL function that walks a list of locales and returns the first non-null translation. Generate the migration with the bundled task:

```bash
mix localize.translate.gen.translate_function
```

This writes a migration that creates `public.translate_field(record, container, field, default_locale, locales)` and its sibling that returns the whole JSON for a locale. The function is `STRICT` and `STABLE`, so the planner is free to push it down or cache results within a row.

Run both migrations:

```bash
mix ecto.migrate
```

## Step 3 — Declare the schema

```elixir
defmodule MyApp.Article do
  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  import Ecto.Changeset

  schema "articles" do
    field :title, :string
    field :body, :string
    translations :translations
    timestamps()
  end

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

Three pieces of magic are happening here:

* **`use Localize.Translate`** records the translatable-field list, the locale list, and the default locale on the module. It also installs `__trans__/1` for runtime reflection and two `@after_compile` callbacks that validate the configuration against the actual struct.

* **`translations :translations`** expands at compile time into an `embeds_one :translations, Translations, …` plus two generated submodules: `MyApp.Article.Translations` (the locale-keyed container) and `MyApp.Article.Translations.Fields` (the shape of each per-locale embed). The default locale is *deliberately omitted* from the container — its values live in the base columns.

* **`cast_embed(:translations, with: &translations_changeset/2)`** lets you control which locales accept input. Listing `:es` and `:fr` here is what enables those locales to be set through the form. You can omit a locale here to make it read-only, or `validate_required` inside the per-locale changeset.

After compilation, `MyApp.Article` exposes:

```elixir
MyApp.Article.__trans__(:fields)         #=> [:title, :body]
MyApp.Article.__trans__(:locales)        #=> [:en, :es, :fr]
MyApp.Article.__trans__(:default_locale) #=> :en
MyApp.Article.__trans__(:container)      #=> :translations
```

These are used internally by `translate/2,3` and `QueryBuilder`, but they're public — feel free to drive UI off them (e.g. iterate the locale list to render input fields).

## Step 4 — Insert and update translated content

Translations are ordinary Ecto changesets all the way down. A controller action might look like:

```elixir
def update(conn, %{"id" => id, "article" => params}) do
  article = Articles.get!(id)

  case article |> Article.changeset(params) |> Repo.update() do
    {:ok, article} -> ...
    {:error, changeset} -> ...
  end
end
```

The `params` shape mirrors the schema:

```elixir
%{
  "title" => "How to write a spell-checker",
  "body" => "Suppose we want to ...",
  "translations" => %{
    "es" => %{"title" => "Cómo escribir un corrector ortográfico", "body" => "..."},
    "fr" => %{"title" => "Comment écrire un correcteur orthographique", "body" => "..."}
  }
}
```

For Phoenix forms, `<.inputs_for field={@form[:translations]}>` followed by another `<.inputs_for>` for each locale gives you the right nesting. Writing a per-locale partial keeps the template tidy.

## Step 5 — Read translations at runtime

`Localize.Translate.translate/2,3` is the read side. It looks up a value in the JSON for the requested locale, falls back to the base column if the locale has no entry, and accepts an explicit fallback chain when you want graceful degradation.

```elixir
import Localize.Translate, only: [translate: 2, translate: 3, translate!: 3]

# Single field
translate(article, :title, :fr)
#=> "Comment écrire un correcteur orthographique"

# Missing locale falls back to the base column
translate(article, :title, :de)
#=> "How to write a spell-checker"

# Explicit fallback chain — try each in order
translate(article, :title, [:de, :es, :en])
#=> "Cómo escribir un corrector ortográfico"

# Whole struct, fields replaced in-place
translate(article, :fr).title
#=> "Comment écrire un correcteur orthographique"

# Strict variant — raise instead of falling back
translate!(article, :title, :de)
#=> ** (RuntimeError) translation doesn't exist for field ':title' in locale :de
```

`translate/2` (whole struct) is recursive: it traverses associations and embeds, translating every translatable child it finds. Unloaded associations (`%Ecto.Association.NotLoaded{}`) are left alone, so it's safe to call before `Repo.preload/2`.

### Where does the "current locale" come from?

`Localize.Translate` does not own a current-locale concept. Every read takes an explicit locale. This is deliberate — it keeps the library composable with whatever locale-resolution strategy the application already uses (`Gettext.get_locale/0`, a plug that reads `Accept-Language`, a session key, a user preference, or a fully-fledged backend like `ex_cldr`). A thin helper in your app is usually all you need:

```elixir
defmodule MyAppWeb.Locale do
  def current, do: Process.get(:locale, :en)

  def with_locale(locale, fun) do
    prev = Process.get(:locale)
    Process.put(:locale, locale)
    try do
      fun.()
    after
      if prev, do: Process.put(:locale, prev), else: Process.delete(:locale)
    end
  end
end
```

Then call `Localize.Translate.translate(article, :title, MyAppWeb.Locale.current())`.

## Step 6 — Query translated content

`Localize.Translate.QueryBuilder.translated/3` builds an `Ecto.Query` fragment that returns the right value for the row, locale, and fallback chain — entirely in SQL. It handles three cases distinctly:

**Single static locale on a field:**

```elixir
import Localize.Translate.QueryBuilder
import Ecto.Query

from a in Article,
  where: translated(Article, a.title, :fr) == "Elixir"
```

Compiles to:

```sql
WHERE COALESCE(a0."translations"->'fr'->>'title', a0."title") = 'Elixir'
```

The COALESCE makes the base column the implicit fallback. Articles with no French translation are still matched if their default `title` happens to equal "Elixir".

**Static locale on the whole record (whole-row presence check):**

```elixir
from a in Article,
  where: not is_nil(translated(Article, a, :es))
```

Compiles to:

```sql
WHERE NOT (NULLIF((a0."translations"->'es'), 'null') IS NULL)
```

`NULLIF((...->'es'), 'null')` is the idiom for "treat JSON null and missing-key both as SQL NULL." It lets you use plain `is_nil/1` in `where:` regardless of whether the JSONB was `{}` or `{"es": null}`.

**Static fallback chain:**

```elixir
from a in Article,
  where: not is_nil(translated(Article, a.title, [:de, :es]))
```

Compiles to a `COALESCE(...)` of one fragment per locale.

**Dynamic (runtime) locale or chain:**

```elixir
locale = MyAppWeb.Locale.current()

from a in Article,
  where: translated(Article, a.title, locale) == ^needle
```

Because the locale is no longer a compile-time literal, `QueryBuilder` falls back to the `translate_field` SQL function. The function loops through the supplied locale array at row-evaluation time:

```sql
WHERE translate_field(a0, 'translations'::varchar, 'title'::varchar, 'en'::varchar, $1::varchar[]) = $2
```

This is why the migration in Step 2 is important — without it, dynamic-locale queries will error at runtime.

### `translated_as/3` for SELECT clauses

When you want the translated value to come back loaded into a struct, alias it to the base column name:

```elixir
from a in Article,
  select: translated_as(Article, a.title, [:fr, :en]),
  where: not is_nil(translated(Article, a.title, [:fr, :en]))
```

The `_as` wrapper turns the fragment into `... AS "title"`, which Ecto then loads into `%Article{title: ...}` without further conversion. Useful for listing pages where the rest of the row stays in the database default.

## Step 7 — Choosing what to translate

A few patterns to keep in mind as the schema grows.

**Translate only what's actually multilingual.** Slugs, timestamps, ids, foreign keys, and other structural columns belong in the base schema. Treat `:translates` as a deliberate list, not a dump.

**Keep fields short.** The JSONB column is fetched in its entirety on every read of the row. A 5-locale article with three 500-byte fields adds ~7.5KB to the row — fine. A 5-locale article with 5MB of HTML per locale, not fine. For long-form body content, consider a `body_translations` *table* keyed by `(article_id, locale)` and continue to embed everything else.

**Be deliberate about whether `nil` means missing or empty.** `Localize.Translate.translate/3` treats both as "fall back to the default value." If you need to distinguish "no Spanish translation yet" from "deliberately empty in Spanish," use `translate!/3` or a separate "translated locales" set.

**Index translations only when you have to.** A `CREATE INDEX articles_es_title_idx ON articles ((translations->'es'->>'title'))` is a perfectly good way to make per-locale searches fast, but each index is per-locale — adding a locale means another migration. Trigram indexes (`pg_trgm`) over the same expression handle ILIKE-style queries efficiently.

## Step 8 — Custom translation containers

If `:translations` collides with an existing field, or if a schema stores translations as a free-form map (e.g. machine-translated keys, no embedded schema), set `:container`:

```elixir
defmodule MyApp.Comment do
  use Ecto.Schema

  use Localize.Translate,
    translates: [:comment],
    container: :transcriptions,
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "comments" do
    field :comment, :string
    field :transcriptions, :map
  end
end
```

With a `:map` field instead of `embeds_one`, you skip the structured-schema generation entirely. The trade-off is that you give up changeset-driven validation per locale — the map accepts anything. This works well when translations come from a pipeline (a translation service, an import job) rather than a form.

`Localize.Translate.translate/3` and `Localize.Translate.QueryBuilder.translated/3` work identically on both shapes — the only difference is what your changesets enforce.

## Step 9 — Forms and Phoenix LiveView

A reusable form partial that walks the locale list:

```heex
<.simple_form for={@form} phx-submit="save">
  <.input field={@form[:title]} label="Title (English)" />
  <.input field={@form[:body]} type="textarea" label="Body (English)" />

  <.inputs_for :let={translations_form} field={@form[:translations]}>
    <%= for locale <- MyApp.Article.__trans__(:locales) -- [:en] do %>
      <.inputs_for :let={fields_form} field={translations_form[locale]}>
        <h3>{Phoenix.Naming.humanize(locale)}</h3>
        <.input field={fields_form[:title]} label="Title" />
        <.input field={fields_form[:body]} type="textarea" label="Body" />
      </.inputs_for>
    <% end %>
  </.inputs_for>

  <:actions>
    <.button>Save</.button>
  </:actions>
</.simple_form>
```

Driving the locale list off `__trans__(:locales)` means adding a locale is *only* a schema change — the form picks it up automatically. The `_:translates_` is `:title, :body` here, but the same partial works for any number of translatable fields by walking `__trans__(:fields)`.

## Step 10 — Testing

Three properties are worth dedicated tests:

**Fallback behaviour.** Insert a record with no translations for the locale-under-test, request it, and assert you got the base value:

```elixir
test "missing locale falls back to base value" do
  article = insert!(%Article{title: "Hello", translations: %{}})
  assert Localize.Translate.translate(article, :title, :de) == "Hello"
end
```

**Query fallback chain returns the right row count.** This catches `NULLIF` and `COALESCE` regressions, which are easy to break with adjacent changes:

```elixir
test "fallback chain finds the first available locale" do
  insert!(%Article{translations: %Article.Translations{es: %{title: "Hola"}}})
  insert!(%Article{translations: %{}})

  query = from a in Article, where: not is_nil(translated(Article, a, [:de, :es]))
  assert Repo.aggregate(query, :count) == 1
end
```

**Round-trip through JSONB.** Insert, fetch, and assert the embedded struct survives the SQL/JSON encoding:

```elixir
test "embedded translations round-trip" do
  article = insert!(%Article{translations: %Article.Translations{
    es: %Article.Translations.Fields{title: "Hola", body: "Mundo"}
  }})

  reloaded = Repo.get!(Article, article.id)
  assert reloaded.translations.es.title == "Hola"
end
```

These three tests give high coverage of the moving parts. The `Localize.Translate` test suite has fuller examples — see `test/localize/translate/query_builder_test.exs` for query-side scenarios and `test/localize/translate/translator_test.exs` for read-side.

## Operational considerations

**Migrations across locales.** Adding a locale doesn't need a database migration — only a schema change. Adding a translatable field *does* require code-level changes (and possibly a backfill if the column was previously empty), but the database still doesn't change.

**Removing a locale.** Stop listing it in `:locales`, then optionally backfill: `UPDATE articles SET translations = translations - 'de'` strips that key from every row.

**Renaming a translatable field.** This is the awkward case — the field name is embedded in the JSON keys. A renaming migration looks like:

```sql
UPDATE articles
SET translations = jsonb_set(
  translations - 'old_name' - 'old_name',
  '{es,new_name}',
  translations->'es'->'old_name'
)
WHERE translations->'es' ? 'old_name';
```

It's not difficult, but it's not free. Worth planning for at design time — favour stable field names.

**Storage.** JSONB has overhead per key. For a 4-locale, 3-field article: ~1KB minimum per row before content. PostgreSQL TOAST-compresses long values, so realistic article translations live somewhere in the 5–20KB range per row. Index and query plans behave normally up to this size.

**Backup and replication.** No special handling needed. JSONB columns round-trip through `pg_dump` and logical replication unchanged.

## Step 11 — Working with `LanguageTag` and parent fallbacks

`Localize.Translate` builds on [`:localize`](https://hex.pm/packages/localize) for locale handling, so a few things come for free without any extra setup.

**Locales validate.** Every locale you pass — in `:locales`, in `translate/N`, in `QueryBuilder.translated/3` — runs through `Localize.validate_locale/1`. Atoms, strings, and `%Localize.LanguageTag{}` structs converge to the same canonical `:cldr_locale_id` atom:

```elixir
{:ok, en_au} = Localize.LanguageTag.new("en-AU")

use Localize.Translate,
  translates: [:title, :body],
  locales: [:en, "en-AU", en_au, :es, :fr],
  default_locale: :en
```

After validation and dedup, `__trans__(:locales)` is `[:en, :"en-AU", :es, :fr]`. The bare atom, the string, and the `LanguageTag` for the same locale collapse to one entry.

Typos raise at compile time:

```elixir
use Localize.Translate,
  translates: [:title],
  locales: [:en, :englsh],  # ** (Localize.InvalidLocaleError) "englsh" is not a valid locale
  default_locale: :en
```

**Fallbacks walk parents.** Any locale you pass to `translate/N` expands into a CLDR parent chain:

```elixir
{:ok, tag} = Localize.LanguageTag.new("en-AU")

# Tries :"en-AU", then :"en-001", then :en, falling back to the base column.
Localize.Translate.translate(article, :title, tag)
```

This avoids needing to store an `en-AU` translation explicitly — the user's preferred regional locale degrades gracefully to the language-level one. The same walk happens for atom locales: `translate(article, :title, :"es-MX")` tries `:"es-MX"` → `:"es-419"` → `:es`.

**`translate/1` and `translate/2` (with a field name) default to `Localize.get_locale/0`.**

```elixir
Localize.with_locale("fr-CA", fn ->
  Localize.Translate.translate(article, :title)  # walks :fr-CA → :fr
end)
```

**`QueryBuilder` does the same walk in SQL, filtered to supported locales.**

```elixir
import Localize.Translate.QueryBuilder

{:ok, tag} = Localize.LanguageTag.new("es-419")

from a in Article,
  where: translated(Article, a.title, tag) == ^needle
```

The locale arg here is a runtime variable, so the macro generates a call to the `translate_field` SQL function. At call time, the tag is expanded to `[:"es-419", :es]`, filtered against the schema's declared `[:en, :es, :fr]`, and only `:es` reaches SQL — keeping the locale array passed to the database minimal.

### Trade-off

Strict validation catches typos but locks you out of free-form locale keys. If you want to key translations by something other than a CLDR locale identifier (e.g. `:legalese_en`), `Localize.Translate` is the wrong tool — store the data in a plain JSONB column instead.

## Where to next

* The `Localize.Translate` moduledoc describes the `use` macro options in full.

* `Localize.Translate.translate/2`, `translate/3`, and `translate!/3` document the read-side functions and their fallback semantics.

* `Localize.Translate.QueryBuilder` documents the query macros and the SQL they emit.

* `Localize.Translate.JSON` covers the `:json`-based adapter Ecto and Postgrex are configured to use — relevant if you want to swap in a different JSON library.

For the rest of the localisation stack — number formatting, dates, plurals, list formatting — pair `Localize.Translate` with [`ex_cldr`](https://hex.pm/packages/ex_cldr) or the `localize` family of libraries.
