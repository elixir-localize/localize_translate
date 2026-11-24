if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule Localize.Translate.QueryBuilder do
    @moduledoc """
    Provides helpers for filtering translations in `Ecto.Queries`.

    This module requires `Ecto.SQL` to be available during the compilation.
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

    * `locale` is either a single locale (atom or string) or a list of locales acting as a
      fallback chain. May be a literal, a variable, or a runtime expression. A runtime
      locale that is not valid, including `nil`, is left out of the chain, so a locale
      taken from a request never raises while the query is built.

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
    walks the chain: the default locale ends it at the base column, a locale with a
    translation ends it with that translation, and the base column is the value when no
    locale matches. For a whole record, it is the first locale's translations, or `NULL`
    when no locale in the chain has any.

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
        #=> WHERE (NOT (NULLIF((a0."translations"->'es'),'null') IS NULL))

        # Query items with a certain translated value
        from a in Article, where: translated(Article, a.title, :fr) == "Elixir"
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (COALESCE(CASE WHEN $1::varchar = $2::varchar THEN a0."title"
        #=>   ELSE a0."translations"->$3->>$4 END, a0."title") = 'Elixir')
        #=> -- $1 = 'fr', $2 = the default locale, $3 = 'fr', $4 = 'title'

        # Query items using a case insensitive comparison
        from a in Article, where: ilike(translated(Article, a.body, :es), "%elixir%")
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (COALESCE(CASE WHEN $1::varchar = $2::varchar THEN a0."body"
        #=>   ELSE a0."translations"->$3->>$4 END, a0."body") ILIKE '%elixir%')

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

        # If MyApp.Article uses structured translations
        from a in Article, where: not is_nil(translated(Article, a, :es))
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (NOT (NULLIF((a0."translations"->'es'),'null') IS NULL))

    ### More complex queries

    The `translated/3` macro can also be used with relations and joined schemas. For more
    complex examples take a look at the QueryBuilder tests (the file is located in
    `test/localize/translate/query_builder_test.exs`).

    """

    defmacro translated(module, translatable, locale, options \\ []) do
      static_locales? = static_locales?(locale)
      field = field(translatable)
      module = Macro.expand(module, __CALLER__)
      validate_field(module, field)
      default = default_locale_param(module, options)
      generate_query(schema(translatable), module, field, locale, default, static_locales?)
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

    # A whole-record query takes the first locale whose translations are present; the
    # default locale plays no part.
    defp generate_query(schema, module, nil, locales, _default, true = _static_locales?)
         when is_list(locales) do
      locales
      |> Enum.map(&whole_record_query(schema, module, &1))
      |> coalesce(locales)
    end

    defp generate_query(schema, module, nil, locale, _default, true = _static_locales?) do
      whole_record_query(schema, module, locale)
    end

    # A field query walks the chain as the `translate_field` database function and
    # `Localize.Translate.translate/3` do: the default locale ends the chain at the base
    # column, a translation that is present ends it with that translation, and the base
    # column is the value when no locale matches. The default is compared at runtime,
    # since it can come from a function or the `:default_locale` option.
    defp generate_query(schema, module, field, locales, default, true = _static_locales?) do
      locales = List.wrap(locales)
      base = quote do: field(unquote(schema), unquote(field))

      locales
      |> Enum.map(&field_query(schema, module, field, &1, default, base))
      |> Kernel.++([base])
      |> coalesce(locales ++ [:base])
    end

    # Called at runtime - we use a database function
    defp generate_query(schema, module, field, locales, default, false = _static_locales?) do
      translate_field(module, schema, field, default, locales)
    end

    defp whole_record_query(schema, module, locale) do
      quote do
        fragment(
          "NULLIF((?->?),'null')",
          field(unquote(schema), unquote(module.__trans__(:container))),
          unquote(to_string(locale))
        )
      end
    end

    defp field_query(schema, module, field, locale, default, base) do
      quote do
        fragment(
          "CASE WHEN ?::varchar = ?::varchar THEN ? ELSE ?->?->>? END",
          ^to_string(unquote(locale)),
          unquote(default),
          unquote(base),
          field(unquote(schema), unquote(module.__trans__(:container))),
          ^to_string(unquote(locale)),
          ^to_string(unquote(field))
        )
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
    # function default is called with `nil`. The empty string stands for no default: the
    # `translate_field` database function is `STRICT`, so it cannot take `NULL`.
    @spec __default_locale__(module()) :: String.t()
    def __default_locale__(module) do
      module
      |> Localize.Translate.default_locale()
      |> default_locale_string()
    end

    @doc false
    @spec __default_locale__(module(), term()) :: String.t()
    def __default_locale__(_module, locale) do
      case Localize.Translate.Locale.normalise(locale) do
        {:ok, locale_id} -> Atom.to_string(locale_id)
        {:error, _exception} -> ""
      end
    end

    defp default_locale_string(nil) do
      ""
    end

    defp default_locale_string(locale_id) do
      Atom.to_string(locale_id)
    end

    defp translate_field(module, schema, nil, default_locale, locales) do
      table_alias = table_alias(schema)
      supported = module.__trans__(:locales)

      funcall =
        "translate_field(#{table_alias}, ?::varchar, ?::varchar, ?::varchar[])"

      quote do
        fragment(
          unquote(funcall),
          ^to_string(unquote(module.__trans__(:container))),
          unquote(default_locale),
          ^Localize.Translate.QueryBuilder.list_to_sql_array(
            unquote(locales),
            unquote(supported)
          )
        )
      end
    end

    defp translate_field(module, schema, field, default_locale, locales) do
      table_alias = table_alias(schema)
      supported = module.__trans__(:locales)

      funcall =
        "translate_field(#{table_alias}, ?::varchar, ?::varchar, ?::varchar, ?::varchar[])"

      quote do
        fragment(
          unquote(funcall),
          ^to_string(unquote(module.__trans__(:container))),
          ^to_string(unquote(field)),
          unquote(default_locale),
          ^Localize.Translate.QueryBuilder.list_to_sql_array(
            unquote(locales),
            unquote(supported)
          )
        )
      end
    end

    @doc false
    def list_to_sql_array(locales, supported \\ nil) do
      locales
      |> Localize.Translate.Locale.expand_valid(supported)
      |> Enum.map(&to_string/1)
    end

    defp coalesce(ast, enum) do
      fun = "COALESCE(" <> fragment_placeholders(enum) <> ")"

      quote do
        fragment(unquote(fun), unquote_splicing(ast))
      end
    end

    defp fragment_placeholders(enum) do
      Enum.map_join(enum, ",", fn _x -> "?" end)
    end

    # Heuristic to guess the Ecto table alias name based upon
    # the binding. If the binding ends in a digit then we assume
    # this is actually the table alias. If it is not, append a `0`
    # and treat it as the table alias. This because its not
    # possible to know the table alias at compile time.
    @digits Enum.map(0..9, &to_string/1)

    defp table_alias({schema, _, _}) do
      schema = to_string(schema)
      if String.ends_with?(schema, @digits), do: schema, else: schema <> "0"
    end

    defp schema({{:., _, [schema, _field]}, _metadata, _args}), do: schema
    defp schema(schema), do: schema

    defp field({{:., _, [_schema, field]}, _metadata, _args}), do: field
    defp field(_), do: nil

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

    defp static_locales?(locale) when is_atom(locale), do: true
    defp static_locales?(locale) when is_binary(locale), do: true

    defp static_locales?(locales) when is_list(locales),
      do: Enum.all?(locales, fn locale -> is_atom(locale) or is_binary(locale) end)

    defp static_locales?(_locales), do: false
  end
end
