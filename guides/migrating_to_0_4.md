# Migrating to 0.4

This guide is for applications upgrading from `localize_translate` 0.3 or 0.2. Most upgrade without changing code: bump the dependency, read the behaviour changes below for anything your application relies on, and when convenient do the database housekeeping at the end.

The largest change is how translated values are queried. Earlier releases called a `translate_field` function that a migration installed in your database. 0.4 writes the same lookup in plain SQL, needs no database function, and is several times faster.

## Upgrading

Update the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:localize_translate, "~> 0.4"}
  ]
end
```

Nothing has to change in the database before you deploy. 0.4 never calls `translate_field`, so it runs whether or not the function is installed, and you can drop the function in a later release of your application.

## Queries no longer call a database function

### Before: `translate_field`

When a query's locale was a runtime value, such as a variable or a `Localize.LanguageTag`, 0.3 compiled `translated/3` to a call to the database function:

```sql
SELECT a0."id",
       translate_field(a0, 'translations'::varchar, 'title'::varchar, $1::varchar, $2::varchar[]) AS "title"
  FROM "articles" AS a0
```

The function took the whole row, turned it into JSON with `row_to_json`, and walked the locales in PL/pgSQL. That had three costs:

* **Speed.** Converting every row to JSON and running PL/pgSQL per row is slow; on a million rows a select took about five seconds.

* **The table alias was guessed.** The row was passed by an alias taken from the query's binding name, so `from b in Book` (which Ecto aliases `a0`, after the `articles` table) failed, and a translated field on a joined schema could fail too.

* **Two query shapes.** A literal locale such as `:fr` compiled to a different, simpler SQL expression that was neither validated nor walked through CLDR parents, and a literal chain such as `[:it, :es]` stopped at the first locale even when it had no translation.

### Now: plain SQL

0.4 builds every query the same way, whether the locale is a literal, a `Localize.LanguageTag` or any other runtime value. The locale is expanded through its CLDR parents in Elixir when the query is built (`fr-CA` → `fr-CA`, `fr`), filtered to the schema's `:locales` with the default locale kept, and passed as one array parameter. The first four locales of that chain are read with plain `jsonb` expressions:

```sql
SELECT a0."id",
       COALESCE(
         CASE WHEN ($1::varchar[])[1] = $2::varchar THEN a0."title"
              ELSE a0."translations"->($3::varchar[])[1]->>$4 END,
         ... the same for positions 2 to 4,
         CASE WHEN cardinality($17::varchar[]) > 4 THEN (... the rest ...) END,
         a0."title"
       ) AS "title"
  FROM "articles" AS a0
```

Each step reads a locale's translation, or the base column for the default locale, and `COALESCE` takes the first that is not null. A position past the end of the chain is null and reads nothing. A chain from a single locale is at most three long, so four steps cover the usual case. A longer chain, such as one built from an `Accept-Language` list, walks the locales after the fourth with a correlated subquery over `unnest`; the `CASE` in front of it skips it when the chain is short enough. The columns are read through Ecto's own alias, so any binding name, join or subquery works.

### Performance

Measured with `EXPLAIN ANALYZE` on a table of one million articles (126 MB) on PostgreSQL 18.4, querying with a `fr-CA` `LanguageTag`. These are single runs on a laptop with the data in memory, so read them as ratios rather than benchmarks:

| Query | 0.3 `translate_field` | 0.4, chain of up to four | 0.4 subquery, longer chains | Hand-written `jsonb` |
|---|---|---|---|---|
| Select every row | 5,290 ms | 197 ms | 556 ms | 195 ms |
| Filter on the translated value | 4,971 ms | 188 ms | 610 ms | 198 ms |
| Sort, first 20 | 6,067 ms | 748 ms | 1,132 ms | 762 ms |

* **A usual query is as fast as hand-written SQL** and about twenty-five times faster than the function. The subquery column is the cost when every row has to be resolved past the fourth locale, the worst case for a long chain.

* **On a generic plan,** which Postgres may choose for a prepared statement it has run several times, the parameters are not known when planning and the array is indexed per row; the same select took 334 ms.

* **Every plan is a sequential scan** reading the same pages; the differences are CPU per row.

### Indexes

As before, the locale is a query parameter, so an expression index such as `((translations->'fr'->>'title'))` is not used by a translated query. That was equally true of `translate_field`. If you added such an index for a hand-written query, it still serves that query.

## Behaviour changes to check

Each of these is in the [CHANGELOG](https://hexdocs.pm/localize_translate/changelog.html). Most fix behaviour that was wrong, but code that relied on the old behaviour will see different results.

### Reads in memory

* **Stored locales the schema does not list are not read.** `translate/2,3` now filter the chain by `:locales`, keeping the default locale, as queries always did. A translation stored under a locale you have since removed from `:locales` is no longer returned; see "Check stored translations" below.

* **A `nil` translation counts as missing.** The chain moves on to its next locale instead of stopping at the base value. `translate(article, :title, [:es, :fr])` returns the French title when the Spanish one is `nil`.

* **Fields that are not translatable return the base value.** `translate/3` raised a `RuntimeError` for them; it now returns the struct's own value, or `nil` for a field the struct lacks. `translate!/3` raises an `ArgumentError` instead of a `RuntimeError`.

* **Invalid locales are left out instead of raised on.** A locale from a request that is not valid, including `nil`, no longer raises in `translate/2,3`; it is skipped. `translate!/3` still raises `Localize.InvalidLocaleError`.

* **A language CLDR has no data for is ignored.** Such a language, for example `"tlh"`, resolves to the CLDR root `und`, and earlier releases read every one of them under the single key `"und"`. It is now left out of the chain, and refused in `:locales` when the schema compiles.

* **Related records use their own locales.** `translate/2` filters each related record by its own `:locales` and default locale, rather than its parent's.

### Queries

* **A literal chain moves on past a missing translation.** `translated(Book, b.title, [:it, :es])` returned the base column when `:it` had no translation; it now returns the Spanish title, as a runtime chain always did.

* **A literal locale walks its CLDR parents.** `translated(Article, a.title, :"es-419")` reads `es`, as a runtime locale does.

* **A schema without `:default_locale` no longer treats `:en` as the default.** Earlier releases passed `en` to the function when no default was declared.

* **The default locale stays in a filtered chain.** On a schema whose default locale is not in `:locales`, a query dropped the default and read a later translation instead of the base column.

### Modules that define `__trans__/1` themselves

`translate/2` now asks for `__trans__(:associations)` to find related records. A module that writes its own `__trans__/1` clauses rather than calling `use Localize.Translate` must answer that key too. Generate the clauses with `Localize.Translate.reflection/1` instead, so the module answers every key a later release adds:

```elixir
defmodule MyApp.Note do
  require Localize.Translate

  defstruct text: nil, translations: %{}

  Localize.Translate.reflection(fields: [:text], default_locale: :en)
end
```

## Database housekeeping

None of this is needed to upgrade, but it removes what 0.4 no longer uses and finds stored data the new rules read differently.

### Drop the `translate_field` function

First check that nothing else in your application calls the function, such as a hand-written query or a database view:

```bash
grep -rn "translate_field" lib priv
```

Then drop both functions in a migration. Use these signatures: the `down/0` that `mix localize.translate.gen.translate_function` generated in 0.2 and 0.3 names signatures without the `record` argument, so rolling that migration back drops nothing.

```elixir
defmodule MyApp.Repo.Migrations.DropTranslateField do
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS public.translate_field(record, varchar, varchar, varchar, varchar[])")
    execute("DROP FUNCTION IF EXISTS public.translate_field(record, varchar, varchar, varchar[])")
  end

  def down do
    # Nothing to restore: 0.4 does not use the function. To bring it back for an
    # earlier release, run that release's mix localize.translate.gen.translate_function.
    :ok
  end
end
```

To confirm it is gone:

```sql
SELECT count(*) FROM pg_proc WHERE proname = 'translate_field';
```

`mix localize.translate.gen.translate_function` is deprecated and will be removed in a later release; remove it from any setup scripts.

### Check stored translations

These queries find data that 0.4 reads differently or not at all. Replace `articles`, `translations`, the default locale `'en'` and the locale list with your own table, container column and schema options.

Text stored for the default locale, which the base columns are meant to hold. With a literal `:default_locale` the generated schema has no place for it, but a map container, a function default or data written past the schema can:

```sql
SELECT id FROM articles
 WHERE jsonb_typeof(translations) = 'object'
   AND jsonb_typeof(translations -> 'en') = 'object';
```

Locale keys the schema does not list, which `translate/2,3` no longer read:

```sql
SELECT key, count(*)
  FROM articles, jsonb_object_keys(translations) AS key
 WHERE jsonb_typeof(translations) = 'object'
   AND key <> ALL (ARRAY['en', 'es', 'fr'])
 GROUP BY key ORDER BY key;
```

Keys that are not in canonical form are never read either, because every read looks up the CLDR locale id. List the distinct keys:

```sql
SELECT DISTINCT key
  FROM articles, jsonb_object_keys(translations) AS key
 WHERE jsonb_typeof(translations) = 'object'
 ORDER BY key;
```

and check each with `Localize.Translate.locale_id/1`. A key whose id differs from the key, or that returns an error, is never read:

```elixir
iex> Localize.Translate.locale_id("fr_CA")
{:ok, :"fr-CA"}

iex> Localize.Translate.locale_id("es-ES")
{:ok, :es}

iex> {:error, _exception} = Localize.Translate.locale_id("tlh")
```

A container that is not a JSON object holds no translations; 0.4 reads it as empty rather than raising:

```sql
SELECT id FROM articles WHERE jsonb_typeof(translations) <> 'object';
```

To repair what these find, rename a key to its canonical form, or remove a locale:

```sql
UPDATE articles
   SET translations = (translations - 'fr_CA') || jsonb_build_object('fr-CA', translations -> 'fr_CA')
 WHERE jsonb_typeof(translations) = 'object' AND translations ? 'fr_CA';

UPDATE articles
   SET translations = translations - 'de'
 WHERE jsonb_typeof(translations) = 'object';
```

Moving text for the default locale into the base columns is an application decision, so it is left to you.

### Keep the rules enforced

For a schema whose `:default_locale` is a function, add `Localize.Translate.validate_translations/1` to its changesets, so a write cannot store text for the record's own default locale:

```elixir
def changeset(article, params) do
  article
  |> cast(params, [:title, :body, :site_id])
  |> cast_embed(:translations)
  |> Localize.Translate.validate_translations()
end
```

It also refuses invalid and unlisted locales in a map container, so it is worth adding to any schema that stores a map.
