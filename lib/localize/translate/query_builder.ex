if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule Localize.Translate.QueryBuilder do
    @moduledoc """
    Provides helpers for filtering translations in `Ecto.Queries`.

    This module requires `Ecto.SQL` to be available during the compilation.
    """

    # Every query has one shape, whether its locale is a literal or a runtime value. The
    # chain is expanded and validated when the query runs, and walked by a subquery over
    # `unnest(locales) WITH ORDINALITY`, which reads the container and base columns
    # through Ecto, so the table alias never has to be known.

    # A whole-record query is the first locale in the chain whose translations are
    # present, or `NULL`; the default locale plays no part.
    @whole_record_sql """
    (SELECT ?->lt_chain.locale \
    FROM unnest(?::varchar[]) WITH ORDINALITY AS lt_chain(locale, position) \
    WHERE NULLIF(?->lt_chain.locale, 'null') IS NOT NULL \
    ORDER BY lt_chain.position LIMIT 1)\
    """

    # A field query is the first non-null value in the chain, where a locale's value is
    # its translation of the field, or the base column for the default locale, and the
    # base column when no locale has one. A null value counts as missing, as it does in
    # `Localize.Translate.translate/3`.
    @field_sql """
    COALESCE(\
    (SELECT lt_value.value \
    FROM unnest(?::varchar[]) WITH ORDINALITY AS lt_chain(locale, position) \
    CROSS JOIN (SELECT ?::varchar AS locale) AS lt_default \
    CROSS JOIN LATERAL (SELECT CASE WHEN lt_chain.locale = lt_default.locale \
    THEN ? ELSE ?->lt_chain.locale->>? END AS value) AS lt_value \
    WHERE lt_value.value IS NOT NULL \
    ORDER BY lt_chain.position LIMIT 1), \
    ?)\
    """

    @doc """
    Generates a SQL fragment for accessing a translated field in an `Ecto.Query`.

    The generated SQL fragment can be coupled with the rest of the functions and operators
    provided by `Ecto.Query` and `Ecto.Query.API`.

    ### Arguments

    * `module` is the `Ecto.Schema` module that uses `Localize.Translate`. Validated at
      compile time.

    * `translatable` is either a query binding (such as `a`) for whole-record access, or a
      field access expression (such as `a.title`) for a specific translatable field.

    * `locale` is a locale (an atom, a string or a `Localize.LanguageTag`) or a list of
      locales acting as a fallback chain. May be a literal, a variable, or a runtime
      expression; either way it is expanded through the CLDR parent chain (`:"es-419"` →
      `:es`) and filtered to the schema's `:locales` when the query is built. A locale that
      is not valid, including `nil`, is left out of the chain, so a locale taken from a
      request never raises.

    * `options` is a literal keyword list of options.

    ### Options

    * `:default_locale` is the locale of the base columns for this query, overriding the
      schema's `:default_locale`. May be a variable or a runtime expression, such as the
      language of the site being queried. Without it the schema's default is used, and a
      function default is called with `nil`, since a query has no record. A value that is
      not a valid locale, or `nil`, means no default: every locale is looked up in the
      translation container.

    ### Returns

    A `fragment/1` AST suitable for use in `Ecto.Query` clauses. For a field, the fragment
    is the first non-null value in the chain, where a locale's value is its translation, or
    the base column for the default locale, and the base column when no locale has one. A
    `NULL` translation counts as missing, as it does in `Localize.Translate.translate/3`. For a whole record, it is the first locale's translations, or
    `NULL` when no locale in the chain has any.

    The chain is walked by a subquery over the locale array, which reads the container and
    base columns through Ecto. No database function is needed, and any binding name, join
    or subquery works.

    ### Safety

    This macro emits errors when used with untranslatable schema modules or fields. Errors
    are emitted during compilation so invalid queries fail before they can run.

    ### Examples

    Assuming the Article schema defined in
    [Structured translations](Localize.Translate.html#module-structured-translations):

        # Return all articles that have a Spanish translation
        from a in Article, where: not is_nil(translated(Article, a, :es))
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (NOT ((SELECT a0."translations"->lt_chain.locale
        #=>   FROM unnest($1::varchar[]) WITH ORDINALITY AS lt_chain(locale, position)
        #=>   WHERE NULLIF(a0."translations"->lt_chain.locale, 'null') IS NOT NULL
        #=>   ORDER BY lt_chain.position LIMIT 1) IS NULL))
        #=> -- $1 = ['es']

        # Query items with a certain translated value
        from a in Article, where: translated(Article, a.title, :fr) == "Elixir"
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (COALESCE((SELECT lt_value.value
        #=>   FROM unnest($1::varchar[]) WITH ORDINALITY AS lt_chain(locale, position)
        #=>   CROSS JOIN (SELECT $2::varchar AS locale) AS lt_default
        #=>   CROSS JOIN LATERAL (SELECT CASE WHEN lt_chain.locale = lt_default.locale
        #=>     THEN a0."title" ELSE a0."translations"->lt_chain.locale->>$3 END AS value)
        #=>     AS lt_value
        #=>   WHERE lt_value.value IS NOT NULL
        #=>   ORDER BY lt_chain.position LIMIT 1), a0."title") = 'Elixir')
        #=> -- $1 = ['fr'], $2 = 'en' (the default locale), $3 = 'title'

        # Query items using a case insensitive comparison
        from a in Article, where: ilike(translated(Article, a.body, :es), "%elixir%")

        # The base columns of each site are in that site's language
        from a in Article,
          where: translated(Article, a.title, :fr, default_locale: site.locale) == "Elixir"

    ### Structured translations vs free-form translations

    `Localize.Translate.QueryBuilder` works with both structured translations and free-form
    translations.

    When using structured translations, the translations are saved as an embedded schema.
    This means that **the locale keys will be always present even if there is no
    translation for that locale.** In the database we have a `NULL` value (`nil` in
    Elixir).

        # If MyApp.Article uses structured translations, a locale with no
        # translation is stored as null and is not counted
        from a in Article, where: not is_nil(translated(Article, a, :es))

    ### More complex queries

    The `translated/4` macro can also be used with relations and joined schemas. For more
    complex examples take a look at the QueryBuilder tests (the file is located in
    `test/localize/translate/query_builder_test.exs`).

    """

    defmacro translated(module, translatable, locale, options \\ []) do
      field = field(translatable)
      module = Macro.expand(module, __CALLER__)
      validate_field(module, field)
      locales = locales_param(module, locale)
      default = default_locale_param(module, options)
      generate_query(schema(translatable), module, field, locales, default)
    end

    @doc """
    Generates a SQL fragment for use in an `Ecto.Query` `select` clause, aliased to the
    original field name.

    Wraps `translated/4` so the returned column carries the base column's name. Ecto can
    therefore load the translated value directly into the schema struct without further
    processing or conversion.

    ### Arguments

    * `module` is the `Ecto.Schema` module that uses `Localize.Translate`.

    * `translatable` is a field access expression such as `a.title`. The base field name is
      used as the column alias.

    * `locale` is either a single locale or a list of locales acting as a fallback chain.

    * `options` is a literal keyword list of options.

    ### Options

    * `:default_locale` is the locale of the base columns for this query. See
      `translated/4`.

    ### Returns

    A `fragment/1` AST that selects the translated value aliased to the original field
    name. See `translated/4` for the underlying SQL produced.

    ### Examples

        # Load each article with its title in French, falling back to the base column
        from a in Article,
          select: %{a | title: translated_as(Article, a.title, :fr)}

        # The same, with the default locale of the site being queried
        from a in Article,
          select: %{a | title: translated_as(Article, a.title, locale, default_locale: site.locale)}

    """

    defmacro translated_as(module, translatable, locale, options \\ []) do
      field = field(translatable)

      translated =
        quote do
          translated(
            unquote(module),
            unquote(translatable),
            unquote(locale),
            unquote(options)
          )
        end

      do_translated_as(translated, field)
    end

    defp do_translated_as(translated, nil) do
      translated
    end

    defp do_translated_as(translated, field) do
      {:fragment, [], ["? AS #{inspect(to_string(field))}", translated]}
    end

    defp generate_query(schema, module, nil, locales, _default) do
      container = container_field(schema, module)

      quote do
        fragment(
          unquote(@whole_record_sql),
          unquote(container),
          unquote(locales),
          unquote(container)
        )
      end
    end

    defp generate_query(schema, module, field, locales, default) do
      container = container_field(schema, module)
      base = quote do: field(unquote(schema), unquote(field))

      quote do
        fragment(
          unquote(@field_sql),
          unquote(locales),
          unquote(default),
          unquote(base),
          unquote(container),
          ^unquote(to_string(field)),
          unquote(base)
        )
      end
    end

    defp container_field(schema, module) do
      quote do
        field(unquote(schema), unquote(module.__trans__(:container)))
      end
    end

    # The locale chain as a pinned query parameter, expanded through the CLDR parent
    # chain, validated and filtered to the schema's locales when the query is built.
    defp locales_param(module, locale) do
      supported = module.__trans__(:locales)

      quote do
        ^Localize.Translate.QueryBuilder.list_to_sql_array(unquote(locale), unquote(supported))
      end
    end

    # The default locale as a pinned query parameter, resolved when the query is built:
    # from the `:default_locale` option when one is given, otherwise from the schema.
    defp default_locale_param(module, options) when is_list(options) do
      if Keyword.has_key?(options, :default_locale) do
        locale = Keyword.fetch!(options, :default_locale)

        quote do
          ^Localize.Translate.QueryBuilder.__default_locale__(unquote(module), unquote(locale))
        end
      else
        quote do
          ^Localize.Translate.QueryBuilder.__default_locale__(unquote(module))
        end
      end
    end

    defp default_locale_param(_module, options) do
      raise ArgumentError,
        message:
          "Localize.Translate.QueryBuilder options must be a literal keyword list, got: #{Macro.to_string(options)}"
    end

    @doc false
    # The schema's default locale as a string for a query, which has no record, so a
    # function default is called with `nil`. `nil` stands for no default.
    @spec __default_locale__(module()) :: String.t() | nil
    def __default_locale__(module) do
      module
      |> Localize.Translate.default_locale()
      |> default_locale_string()
    end

    @doc false
    @spec __default_locale__(module(), term()) :: String.t() | nil
    def __default_locale__(_module, locale) do
      case Localize.Translate.Locale.normalise(locale) do
        {:ok, locale_id} -> Atom.to_string(locale_id)
        {:error, _exception} -> nil
      end
    end

    defp default_locale_string(nil) do
      nil
    end

    defp default_locale_string(locale_id) do
      Atom.to_string(locale_id)
    end

    @doc false
    def list_to_sql_array(locales, supported \\ nil) do
      locales
      |> Localize.Translate.Locale.expand_valid(supported)
      |> Enum.map(&to_string/1)
    end

    defp schema({{:., _, [schema, _field]}, _metadata, _args}) do
      schema
    end

    defp schema(schema) do
      schema
    end

    defp field({{:., _, [_schema, field]}, _metadata, _args}) do
      field
    end

    defp field(_) do
      nil
    end

    defp validate_field(module, field) do
      cond do
        is_nil(field) ->
          nil

        not Localize.Translate.translatable?(module, field) ->
          raise ArgumentError,
            message: "'#{inspect(module)}' module must declare '#{field}' as translatable"

        true ->
          nil
      end
    end
  end
end
