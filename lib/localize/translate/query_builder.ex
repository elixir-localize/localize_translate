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
      fallback chain. May be a literal, a variable, or a runtime expression.

    ### Returns

    A `fragment/1` AST suitable for use in `Ecto.Query` clauses. The fragment evaluates to
    the translated value with fallback to the base column, or `NULL` when no translation
    exists for the requested locales.

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
        #=> WHERE (COALESCE(a0."translations"->$1->>$2, a0."title") = 'Elixir')

        # Query items using a case insensitive comparison
        from a in Article, where: ilike(translated(Article, a.body, :es), "%elixir%")
        #=> SELECT a0."id", a0."title", a0."body", a0."translations"
        #=> FROM "articles" AS a0
        #=> WHERE (COALESCE(a0."translations"->$1->>$2, a0."body") ILIKE '%elixir%')

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

    defmacro translated(module, translatable, locale) do
      static_locales? = static_locales?(locale)

      with field <- field(translatable) do
        module = Macro.expand(module, __CALLER__)
        validate_field(module, field)
        generate_query(schema(translatable), module, field, locale, static_locales?)
      end
    end

    @doc """
    Generates a SQL fragment for use in an `Ecto.Query` `select` clause, aliased to the
    original field name.

    Wraps `translated/3` so the returned column carries the base column's name. Ecto can
    therefore load the translated value directly into the schema struct without further
    processing or conversion.

    ### Arguments

    * `module` is the `Ecto.Schema` module that uses `Localize.Translate`.

    * `translatable` is a field access expression such as `a.title`. The base field name is
      used as the column alias.

    * `locale` is either a single locale or a list of locales acting as a fallback chain.

    ### Returns

    A `fragment/1` AST that selects the translated value aliased to the original field
    name. See `translated/3` for the underlying SQL produced.

    """

    defmacro translated_as(module, translatable, locale) do
      field = field(translatable)
      translated = quote do: translated(unquote(module), unquote(translatable), unquote(locale))
      do_translated_as(translated, field)
    end

    defp do_translated_as(translated, nil) do
      translated
    end

    defp do_translated_as(translated, field) do
      {:fragment, [], ["? AS #{inspect(to_string(field))}", translated]}
    end

    defp generate_query(schema, module, field, locales, true = static_locales?)
         when is_list(locales) do
      for locale <- locales do
        generate_query(schema, module, field, locale, static_locales?)
      end
      |> coalesce(locales)
    end

    defp generate_query(schema, module, nil, locale, true = _static_locales?) do
      quote do
        fragment(
          "NULLIF((?->?),'null')",
          field(unquote(schema), unquote(module.__trans__(:container))),
          unquote(to_string(locale))
        )
      end
    end

    defp generate_query(schema, module, field, locale, true = _static_locales?)
         when is_atom(locale) or is_binary(locale) do
      if locale == module.__trans__(:default_locale) do
        quote do
          field(unquote(schema), unquote(field))
        end
      else
        quote do
          fragment(
            "COALESCE(?->?->>?, ?)",
            field(unquote(schema), unquote(module.__trans__(:container))),
            ^to_string(unquote(locale)),
            ^to_string(unquote(field)),
            field(unquote(schema), unquote(field))
          )
        end
      end
    end

    # Called at runtime - we use a database function
    defp generate_query(schema, module, field, locales, false = _static_locales?) do
      default_locale = to_string(module.__trans__(:default_locale) || :en)
      translate_field(module, schema, field, default_locale, locales)
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
          ^to_string(unquote(default_locale)),
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
          ^to_string(unquote(default_locale)),
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
      |> Localize.Translate.Locale.expand(supported)
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
