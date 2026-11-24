defmodule Localize.Translate do
  @moduledoc """
  Manage translations embedded into translation structs.

  Although it can be used with any struct **`Localize.Translate` shines when paired with an
  `Ecto.Schema`**. It allows you to keep the translations into a field of the schema and avoids
  requiring extra tables for translation storage and complex _joins_ when retrieving translations
  from the database.

  The runtime API lives on `Localize.Translate` itself:

  * `translate/1`, `translate/2` return a translated copy of an entire struct, or a single
    field when the second argument is a field name.

  * `translate/3` and `translate!/3` return a single translated field with an explicit
    locale or locale fallback chain.

  * `translatable?/2` reports whether a field is declared as translatable.

  * `default_locale/1` resolves the locale of a struct's base fields, and `locale_chain/2`
    expands a locale into the CLDR fallback chain the reads walk, for code that builds its
    own lookups, such as a data-layer calculation.

  For `Ecto.Query` support, `Localize.Translate.QueryBuilder` provides the `translated/4`
  and `translated_as/4` macros (requires `Ecto.SQL`).

  ### Locale handling

  `Localize.Translate` builds on [`:localize`](https://hex.pm/packages/localize) for
  CLDR-aware locale handling. Three properties follow:

  * **All locale inputs validate.** Atoms (`:en`), strings (`"en"`), and
    `%Localize.LanguageTag{}` structs are accepted anywhere a locale is expected — in
    `:locales`, `translate/N`, and `QueryBuilder.translated/4`. Each value is run
    through `Localize.validate_locale/1` and unwrapped to its `:cldr_locale_id` atom.
    An invalid locale never raises at runtime: `translate/2,3` and
    `QueryBuilder.translated/4` leave it out of the fallback chain, so it resolves to
    the next locale or the base value, and only `translate!/3` raises it. An invalid
    locale in the `:locales` option raises when the schema compiles.

  * **Fallbacks walk the CLDR parent chain.** A locale expands into a fallback chain
    by walking parents (e.g. `:"en-AU"` → `:"en-001"` → `:en`, stopping before the
    `:und` root). For `QueryBuilder`, the chain is filtered to the locales declared in
    `:locales` so unsupported parents don't generate dead branches.

  * **The current locale is `Localize.get_locale/0`.** `translate/1` and `translate/2`
    (with a field name) default the locale from `Localize.get_locale/0` and walk its
    parents.

  Mixed `:locales` lists like `[:en, %Localize.LanguageTag{cldr_locale_id: :fr}]` are
  supported. After validation each entry is reduced to an atom, deduplicated, and
  sorted.

  When used, `Localize.Translate` accepts the following options:

  * `:translates` (required) - list of the fields that will be translated.

  * `:locales` (optional) - the list of locales for which translations will be stored. Required
    if you use the `translations/1` macro to auto-generate the embedded schema. Locales are
    atoms (for example `:en`, `:"en-AU"`).

  * `:default_locale` (optional) - declares the locale of the base untranslated columns. The
    fields in the main schema are considered to be in this locale, and no separate translation
    embed is generated for it. Either a locale, or a `{module, function, arguments}` tuple for
    a default known only at runtime, such as the language of the site a record belongs to. The
    function is called as `apply(module, function, [subject | arguments])` with the struct
    being translated, or `nil` for a query, and returns a locale or `nil`. See
    `default_locale/1`. With a function, every locale in `:locales` gets an embed, so keep the
    default locale's text in the base fields, not in the container.

  * `:container` (optional) - the name of the field that holds the translations. Defaults to
    `:translations`.

  ### Structured translations

  Structured translations are the preferred and recommended way of using `Localize.Translate`. To
  use structured translations, use the `translations/1` macro when defining a schema. The
  `translations/1` macro will define an embedded schema with the name being the parameter passed
  to the `translations/1` macro. Within the `:translations` field that is generated, an
  `embeds_one/2` call is added for each non-default locale in `:locales`. Here's an example
  schema configuration:

      defmodule MyApp.Article do
        use Ecto.Schema
        use Localize.Translate,
          translates: [:title, :body],
          locales: [:en, :es, :fr],
          default_locale: :en

        schema "articles" do
          field :title, :string
          field :body, :string
          translations :translations
        end
      end

  When expanded by the Elixir compiler, the example above will look like the following code. It
  is provided here only as an example to show what the `translations/1` macro compiles to.

      defmodule MyApp.Article do
        use Ecto.Schema

        schema "articles" do
          field :title, :string
          field :body, :string

          embeds_one :translations, Translations, on_replace: :update, primary_key: false do
            embeds_one :es, MyApp.Article.Translations.Fields
            embeds_one :fr, MyApp.Article.Translations.Fields
          end
        end
      end

      defmodule MyApp.Article.Translations.Fields do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field :title, :string
          field :body, :string
        end
      end

  ### Reflection

  Any module that uses `Localize.Translate` will have an autogenerated `__trans__` function that
  can be used for runtime introspection of the translation metadata.

  * `__trans__(:fields)` - Returns the list of translatable fields.

  * `__trans__(:container)` - Returns the name of the translation container.

  * `__trans__(:locales)` - Returns the configured locales (or `nil` if not given).

  * `__trans__(:default_locale)` - Returns the `:default_locale` option as given: a locale, a
    `{module, function, arguments}` tuple, or `nil`. `default_locale/1` resolves it. The fields
    in the main schema are considered to be in this locale.

  * `__trans__(:associations)` - Returns the fields that hold related records, which
    `translate/2` translates too. For an Ecto schema these are its associations and
    embeds. A module that defines `__trans__/1` itself, such as one built by a data layer
    other than Ecto, answers with its own list.

  """

  @typedoc """
  A translatable struct that uses `Localize.Translate`.

  """
  @type translatable() :: struct()

  @typedoc """
  A struct field as an atom.

  """
  @type field :: atom()

  @typedoc """
  A locale identifier as an atom (for example `:en`, `:"en-AU"`) or a string.

  """
  @type locale :: atom() | String.t()

  @typedoc """
  When translating or querying either a single locale or a list of locales can be provided.

  A list of locales acts as a fallback chain: each locale is tried in order until a translation
  is found.

  """
  @type locale_list :: locale() | [locale(), ...]

  @doc false
  defmacro using(options) do
    quote do
      import Localize.Translate,
        only: [
          trans_fields: 1,
          trans_container: 1,
          trans_locales: 1,
          trans_default_locale: 1,
          trans_store: 1,
          trans_store_options: 1
        ]

      Module.put_attribute(__MODULE__, :trans_fields, trans_fields(unquote(options)))
      Module.put_attribute(__MODULE__, :trans_container, trans_container(unquote(options)))
      Module.put_attribute(__MODULE__, :trans_locales, trans_locales(unquote(options)))

      Module.put_attribute(
        __MODULE__,
        :trans_default_locale,
        trans_default_locale(unquote(options))
      )

      Module.put_attribute(__MODULE__, :trans_store, trans_store(unquote(options)))

      Module.put_attribute(
        __MODULE__,
        :trans_store_options,
        trans_store_options(unquote(options))
      )

      @after_compile {Localize.Translate, :__validate_translatable_fields__}
      @after_compile {Localize.Translate, :__validate_translation_container__}

      @spec __trans__(:fields) :: list(atom)
      def __trans__(:fields) do
        @trans_fields
      end

      @spec __trans__(:container) :: atom
      def __trans__(:container) do
        @trans_container
      end

      @spec __trans__(:locales) :: [atom(), ...] | nil
      def __trans__(:locales) do
        @trans_locales
      end

      @spec __trans__(:default_locale) ::
              atom() | String.t() | {module(), atom(), list()} | nil
      def __trans__(:default_locale) do
        @trans_default_locale
      end

      @spec __trans__(:store) :: module()
      def __trans__(:store) do
        @trans_store
      end

      @spec __trans__(:store_options) :: keyword()
      def __trans__(:store_options) do
        @trans_store_options
      end

      @spec __trans__(:associations) :: [atom()]
      def __trans__(:associations) do
        Localize.Translate.__associations__(__MODULE__)
      end
    end
  end

  defmacro __using__(options) do
    quote do
      require Localize.Translate

      Localize.Translate.using(unquote(options))
      import Localize.Translate, only: :macros
    end
  end

  @doc false
  def default_trans_options do
    [build_field_schema: true]
  end

  @doc false
  def known_trans_options do
    [:build_field_schema, :fields_module]
  end

  @doc """
  Defines the embedded translation container field on an `Ecto.Schema`.

  Within an `Ecto.Schema` block, expands into an `embeds_one/3` declaration for the named
  container field plus auto-generated `Translations` and `Translations.Fields` embedded
  schemas — one `embeds_one` per non-default locale, each holding the translatable string
  fields declared in `:translates`.

  ### Arguments

  * `field_name` is the name of the container field on the parent schema, given as an atom
    (commonly `:translations`).

  * `translation_module` (optional) is the alias name of the generated translation schema.
    Defaults to `Translations`. Pass an alias to use a different module name under the parent.

  * `locales_or_options` (optional) is either an explicit list of locale atoms, or a keyword
    list of options. When omitted, the locales configured via the `:locales` option on
    `use Localize.Translate` are used.

  ### Options

  * `:build_field_schema` — when `true` (the default), generates both the translation
    schema (`Translations`, or the `translation_module` given) and its inner `Fields`
    schema. When `false`, neither is generated: the container field still embeds the
    translation schema, so define it yourself with one `embeds_one` per non-default locale,
    pointing at a `Fields` schema of your own, which may carry extra fields such as an
    update timestamp.

  * `:fields_module` — a per-locale embedded schema of your own, used in place of the
    generated `Fields` schema. The translation schema is still generated, with each
    non-default locale embedding this module. It must be an `Ecto.Schema` that defines
    every field in `:translates` as a `:string`, which is checked when the parent schema
    compiles, and it may define any other fields, such as an update timestamp or the name
    of the translator. It must be compiled before the parent schema, so it cannot be a
    module nested inside it. It cannot be combined with `build_field_schema: false`.

  Any other option raises an `ArgumentError` when the schema compiles.

  ### Returns

  * The quoted `embeds_one/3` declaration for the container field, together with the
    generated translation schema and, unless `:fields_module` or `build_field_schema: false`
    is given, its `Fields` schema. One embed is generated per locale, leaving out a literal
    `:default_locale`; with a function default every locale gets one, since the default is
    known only at runtime.

  ### Examples

      defmodule MyApp.Article do
        use Ecto.Schema
        use Localize.Translate,
          translates: [:title, :body],
          locales: [:en, :es, :fr],
          default_locale: :en

        schema "articles" do
          field :title, :string
          field :body, :string
          translations :translations
        end
      end

  A per-locale schema of your own keeps state beside each locale's translations:

      defmodule MyApp.Article.TranslationFields do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field :title, :string
          field :body, :string
          field :translated_by, :string
          field :machine_translated, :boolean, default: false
        end
      end

      defmodule MyApp.Article do
        use Ecto.Schema
        use Localize.Translate,
          translates: [:title, :body],
          locales: [:en, :es, :fr],
          default_locale: :en

        schema "articles" do
          field :title, :string
          field :body, :string
          translations :translations, Translations, fields_module: MyApp.Article.TranslationFields
        end
      end

  `Localize.Translate.translate/3` and `Localize.Translate.QueryBuilder` read only the
  fields in `:translates`. A query on a whole locale, `translated(Article, a, :es)`, reads
  the locale's whole object, so a locale that holds only such state is not `NULL`.

  """
  defmacro translations(field_name, translation_module \\ nil, locales_or_options \\ []) do
    module = __CALLER__.module
    translation_module = trans_module(translation_module)

    if Keyword.keyword?(locales_or_options) do
      quote do
        translations(
          unquote(field_name),
          unquote(translation_module),
          Module.get_attribute(unquote(module), :trans_locales),
          unquote(locales_or_options)
        )
      end
    else
      quote do
        translations(
          unquote(field_name),
          unquote(translation_module),
          unquote(locales_or_options),
          []
        )
      end
    end
  end

  @doc """
  Defines the embedded translation container field with explicit locales.

  Four-arity form of `translations/3`. Use this when you want to override the configured
  `:locales` option for a single schema, or to pass an options keyword list alongside an
  explicit locale list.

  ### Arguments

  * `field_name` is the name of the container field on the parent schema, as an atom.

  * `translation_module` is the alias name of the generated translation schema.

  * `locales` is the explicit list of locale atoms for which translation embeds are
    generated. A literal `:default_locale` is left out.

  * `options` is a keyword list of options.

  ### Options

  * `:build_field_schema` and `:fields_module`, as described for `translations/3`.

  ### Returns

  * The quoted `embeds_one/3` declaration for the container field and the generated
    schemas, as for `translations/3`, with one embed per locale in `locales`.

  ### Examples

      defmodule MyApp.Article do
        use Ecto.Schema
        use Localize.Translate,
          translates: [:title, :body],
          locales: [:en, :es, :fr],
          default_locale: :en

        schema "articles" do
          field :title, :string
          field :body, :string

          # Only Spanish translations for this schema, whatever :locales says
          translations :translations, Translations, [:es], []
        end
      end

  """
  defmacro translations(field_name, translation_module, locales, options) do
    caller = __CALLER__.module
    Localize.Translate.__validate_trans_options__(caller, options)

    options = Keyword.merge(Localize.Translate.default_trans_options(), options)
    build_field_schema = Keyword.fetch!(options, :build_field_schema)
    fields_module = Keyword.get(options, :fields_module)

    quote do
      if unquote(translation_module) && unquote(build_field_schema) do
        @before_compile {Localize.Translate, :__build_embedded_schema__}
      end

      @translation_module Module.concat(unquote(caller), unquote(translation_module))
      @translation_fields_module unquote(fields_module)
      @locales unquote(locales)

      embeds_one(unquote(field_name), @translation_module, on_replace: :update)
    end
  end

  @doc false
  defmacro __build_embedded_schema__(env) do
    translation_module = Module.get_attribute(env.module, :translation_module)
    fields_module = Module.get_attribute(env.module, :translation_fields_module)
    fields = Module.get_attribute(env.module, :trans_fields)
    locales = Module.get_attribute(env.module, :locales)
    default_locale = Module.get_attribute(env.module, :trans_default_locale)

    if is_nil(fields_module) do
      generated_fields = Module.concat(translation_module, Fields)

      quote do
        unquote(translation_schema(translation_module, generated_fields, locales, default_locale))
        unquote(fields_schema(generated_fields, fields))
      end
    else
      __validate_fields_module__(env.module, fields_module, fields)
      translation_schema(translation_module, fields_module, locales, default_locale)
    end
  end

  # The translation schema: one embed per non-default locale, each of the
  # per-locale schema, which is the generated `Fields` or the caller's own.
  defp translation_schema(translation_module, fields_module, locales, default_locale) do
    excluded_locale = literal_default_locale(default_locale)

    quote do
      defmodule unquote(translation_module) do
        @moduledoc false

        use Ecto.Schema

        @primary_key false
        embedded_schema do
          for locale_name <- List.wrap(unquote(locales)),
              locale_name != unquote(excluded_locale) do
            embeds_one(locale_name, unquote(fields_module), on_replace: :update)
          end
        end
      end
    end
  end

  # A function default is known only at runtime, so no locale's embed can be left out.
  defp literal_default_locale({_module, _function, _arguments}) do
    nil
  end

  defp literal_default_locale(default_locale) do
    default_locale
  end

  defp fields_schema(fields_module, fields) do
    quote do
      defmodule unquote(fields_module) do
        @moduledoc false

        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          for a_field <- unquote(fields) do
            field(a_field, :string)
          end
        end

        def changeset(fields, params) do
          fields
          |> cast(params, unquote(fields))
          |> validate_required(unquote(fields))
        end
      end
    end
  end

  @doc """
  Checks whether the given field is translatable or not.

  A string field is compared with the declared field names as strings, so a field name
  taken from a request never creates an atom.

  ### Arguments

  * `module_or_translatable` is either a module that uses `Localize.Translate` or a struct of
    that module.

  * `field` is the field name as an atom or string.

  ### Returns

  * `true` if the given field is translatable.

  * `false` if the given field is not translatable, if the module or struct does not use
    `Localize.Translate`, or if either argument is not a module or a field name.

  ### Examples

  Assuming the Article schema defined in [Structured translations](#module-structured-translations).

      iex> Localize.Translate.translatable?(Article, :title)
      true

      iex> Localize.Translate.translatable?(Article, "title")
      true

      iex> article = %Article{}
      iex> Localize.Translate.translatable?(article, :not_existing)
      false

      iex> Localize.Translate.translatable?(Date, :day)
      false

  """
  @spec translatable?(module() | translatable(), String.t() | atom()) :: boolean()
  def translatable?(module_or_translatable, field)

  def translatable?(%{__struct__: module}, field) do
    translatable?(module, field)
  end

  def translatable?(module, field) when is_atom(module) and is_binary(field) do
    module
    |> translatable_fields()
    |> Enum.any?(&(Atom.to_string(&1) == field))
  end

  def translatable?(module, field) when is_atom(module) and is_atom(field) do
    module
    |> translatable_fields()
    |> Enum.member?(field)
  end

  def translatable?(_module_or_translatable, _field) do
    false
  end

  defp translatable_fields(module) do
    if translatable_module?(module) do
      module.__trans__(:fields)
    else
      []
    end
  end

  @doc """
  Translates a whole struct into the current locale.

  Equivalent to `translate(translatable, locale)` with `locale` resolved from
  `Localize.get_locale/0` when the optional `:localize` dependency is loaded, falling back
  to the schema's `:default_locale` otherwise.

  ### Arguments

  * `translatable` is a struct that uses `Localize.Translate`.

  ### Returns

  * The translated struct. A value that is not a struct using `Localize.Translate` is
    returned unchanged.

  ### Examples

      iex> comment = %Localize.Translate.Comment{
      ...>   comment: "Hello",
      ...>   transcriptions: %{"fr" => %{"comment" => "Bonjour"}}
      ...> }
      iex> Localize.put_locale(:fr)
      iex> Localize.Translate.translate(comment).comment
      "Bonjour"

  """
  @spec translate(translatable()) :: translatable()
  def translate(translatable) do
    translate(translatable, default_locale_for(translatable))
  end

  @doc """
  Translates a whole struct (or a single field) into the given locale.

  Returns the struct with every translatable field — and every translatable association or
  embed — replaced by the value for the requested locale, falling back to the default
  value when the locale has no entry. If the second argument is the name of a translatable
  field, returns that single translated field using the current locale (see `translate/3`
  for an explicit locale).

  ### Arguments

  * `translatable` is a struct that uses `Localize.Translate`.

  * `locale_or_field` is one of:

    * an atom or string locale (e.g. `:es`, `"fr"`),

    * a list of locales acting as a fallback chain,

    * a `%Localize.LanguageTag{}` — when the optional `:localize` dependency is loaded,
      expanded into a fallback chain by walking the CLDR parent chain, or

    * an atom field name — translates a single field using the current locale (see
      `translate/3`).

  ### Returns

  * The translated struct, or the translated value of a single field. A locale that is
    not valid is left out of the chain, so the struct is returned untranslated when no
    valid locale is left. A value that is not a struct is returned unchanged.

  ### Examples

      # Translate the entire article into Spanish
      Localize.Translate.translate(article, :es)

      # Fallback chain — Deutsch missing, Spanish wins
      Localize.Translate.translate(article, [:de, :es])

  """
  @spec translate(translatable(), locale_list() | field() | struct()) ::
          translatable() | any()
  def translate(%{__struct__: _module} = translatable, locale_or_field) do
    case classify_locale_or_field(translatable, locale_or_field) do
      {:field, field} -> translate(translatable, field, default_locale_for(translatable))
      {:locale, chain} -> do_translate(translatable, chain)
    end
  end

  def translate(other, _locale_or_field) do
    other
  end

  defp do_translate(%{__struct__: module} = translatable, locale) do
    if Keyword.has_key?(module.__info__(:functions), :__trans__) do
      default_locale = default_locale(translatable)
      translatable = load_translations(translatable)

      translatable
      |> translate_fields(locale, default_locale)
      |> translate_assocs(locale)
    else
      translatable
    end
  end

  @doc """
  Translates a single field into the given locale.

  Looks up the field's translation in the given locale (or first match in a fallback
  chain) and returns it. Returns the base value if no translation is available.

  ### Arguments

  * `translatable` is a struct that uses `Localize.Translate`.

  * `field` is the name of the translatable field as an atom or a string.

  * `locale` is either a single locale or a list of locales acting as a fallback chain.

  ### Returns

  * The translated value, or the value from the base column when no translation exists
    for any locale in the chain. A `nil` translation counts as missing, so the chain moves
    on to its next locale. A locale that is not valid, including `nil`, is left out of the
    chain rather than raised on, so a locale taken from a request is safe to pass.

  * The base value of a field that is not declared translatable, or `nil` for a field the
    struct does not have or a value that is not a struct. A string field name never
    creates an atom.

  ### Examples

      # Spanish title
      Localize.Translate.translate(article, :title, :es)

      # Unknown locale falls back to the base column
      Localize.Translate.translate(article, :title, :de)

      # Fallback chain
      Localize.Translate.translate(article, :title, [:de, :es])

      # A field that is not translatable is its base value
      Localize.Translate.translate(article, :id, :es)

  """
  @spec translate(translatable(), field() | String.t(), locale_list() | struct()) :: any()
  def translate(translatable, field, locale) do
    case translatable_field(translatable, field) do
      {:ok, field} -> translate_translatable(translatable, field, locale)
      :error -> base_value(translatable, field)
    end
  end

  defp translate_translatable(translatable, field, locale) do
    chain = expand_locale(locale)
    default_locale = default_locale(translatable)
    translatable = load_translations(translatable)

    case translate_field(translatable, chain, field, default_locale) do
      :error -> Map.fetch!(translatable, field)
      nil -> Map.fetch!(translatable, field)
      translation -> translation
    end
  end

  @doc """
  Translates a single field into the given locale, raising if no translation is available.

  Strict variant of `translate/3`. Where `translate/3` falls back to the base value when a
  translation is missing, `translate!/3` raises so callers can distinguish "no
  translation" from "translation equals the default".

  ### Arguments

  * `translatable` is a struct that uses `Localize.Translate`.

  * `field` is the name of the translatable field as an atom or a string.

  * `locale` is either a single locale or a list of locales acting as a fallback chain.

  ### Returns

  * The translated value.

  * Raises a `RuntimeError` if no translation exists for any locale in the chain. A `nil`
    translation counts as missing.

  * Raises an `ArgumentError` if `translatable` is not a struct that uses
    `Localize.Translate` or `field` is not one of its translatable fields.

  * Raises a `Localize.InvalidLocaleError` if any locale in the chain is not valid,
    including `nil`.

  ### Examples

      Localize.Translate.translate!(article, :title, :de)
      ** (RuntimeError) translation doesn't exist for field ':title' in locale :de

  """
  @spec translate!(translatable(), field() | String.t(), locale_list() | struct()) :: any()
  def translate!(translatable, field, locale) do
    case translatable_field(translatable, field) do
      {:ok, field} -> translate_translatable!(translatable, field, locale)
      :error -> raise ArgumentError, not_translatable_error(translatable, field)
    end
  end

  defp translate_translatable!(translatable, field, locale) do
    chain = expand_locale!(locale)
    default_locale = default_locale(translatable)
    translatable = load_translations(translatable)

    case translate_field(translatable, chain, field, default_locale) do
      :error -> raise no_translation_error(field, locale)
      translation -> translation
    end
  end

  # A translatable field of a struct that uses `Localize.Translate`, as an atom. A string
  # is matched against the declared field names, so it never creates an atom.
  defp translatable_field(%{__struct__: module}, field) when is_atom(field) or is_binary(field) do
    module
    |> translatable_fields()
    |> Enum.find(&(&1 == field or Atom.to_string(&1) == field))
    |> found_field()
  end

  defp translatable_field(_translatable, _field) do
    :error
  end

  defp found_field(nil) do
    :error
  end

  defp found_field(field) do
    {:ok, field}
  end

  # The base value of a field that is not translatable: the struct's own value for a key
  # it defines, matched by string for a string name, and `nil` otherwise.
  defp base_value(%{__struct__: _module} = struct, field) do
    struct
    |> Map.from_struct()
    |> Enum.find_value(fn {key, value} ->
      if key == field or Atom.to_string(key) == field do
        {:ok, value}
      end
    end)
    |> found_value()
  end

  defp base_value(_other, _field) do
    nil
  end

  defp found_value({:ok, value}) do
    value
  end

  defp found_value(nil) do
    nil
  end

  @doc """
  Returns the default locale of a translatable struct or module: the locale its base
  fields are written in.

  The schema's `:default_locale` option is either a locale or a `{module, function,
  arguments}` tuple. A tuple is called as `apply(module, function, [subject | arguments])`,
  where the subject is the struct, or `nil` when a module is given, as it is for a query.

  ### Arguments

  * `translatable` is a struct that uses `Localize.Translate`, or a module that does.

  ### Returns

  * The default locale as a CLDR locale id atom, such as `:en` or `:"fr-CA"`, or

  * `nil` when the schema has no default locale, or its function returns `nil` or a value
    that is not a valid locale, or when `translatable` is not a struct or module that uses
    `Localize.Translate`. With no default locale every locale is looked up in the
    translation container, so the base fields must not also have an entry there.

  ### Examples

      iex> Localize.Translate.default_locale(%Localize.Translate.Comment{})
      :en

      iex> Localize.Translate.default_locale(Localize.Translate.Comment)
      :en

  """
  @spec default_locale(translatable() | module() | term()) :: atom() | nil
  def default_locale(%{__struct__: module} = translatable) do
    if translatable_module?(module) do
      resolve_default_locale(module, translatable)
    end
  end

  def default_locale(module) when is_atom(module) do
    if translatable_module?(module) do
      resolve_default_locale(module, nil)
    end
  end

  def default_locale(_other) do
    nil
  end

  @doc """
  Expands a locale, or a list of locales, into the CLDR fallback chain that
  `translate/2,3` and `QueryBuilder.translated/4` walk.

  Each locale is validated and followed up its CLDR parent chain, stopping before the root
  (`:"en-AU"` → `:"en-001"` → `:en`). A list is expanded locale by locale and
  deduplicated in order. A locale that is not valid, `nil` included, is left out, as the
  reads leave it out, so a locale taken from a request is safe to pass.

  ### Arguments

  * `locale_or_locales` is a locale (an atom, a string or a `Localize.LanguageTag`) or a
    list of them.

  * `options` is a keyword list of options.

  ### Options

  * `:supported` is a list of locale atoms to keep, such as a schema's
    `__trans__(:locales)`, dropping parents no translation is stored for. `nil` or an
    empty list, the default, keeps the whole chain.

  ### Returns

  * The chain as a list of CLDR locale id atoms, which is empty when no locale is valid.

  ### Examples

      iex> Localize.Translate.locale_chain("fr-CA")
      [:"fr-CA", :fr]

      iex> Localize.Translate.locale_chain([:"en-AU", :es])
      [:"en-AU", :"en-001", :en, :es]

      iex> Localize.Translate.locale_chain(["not a locale", :es])
      [:es]

      iex> Localize.Translate.locale_chain(:"en-AU", supported: [:en, :es])
      [:en]

  """
  @spec locale_chain(locale_list() | struct() | nil, keyword()) :: [atom()]
  def locale_chain(locale_or_locales, options \\ []) do
    supported = supported_locales(options)
    Localize.Translate.Locale.expand_valid(locale_or_locales, supported)
  end

  defp supported_locales(options) when is_list(options) do
    case Keyword.get(options, :supported) do
      supported when is_list(supported) -> supported
      _other -> nil
    end
  end

  defp supported_locales(_options) do
    nil
  end

  defp resolve_default_locale(module, subject) do
    case module.__trans__(:default_locale) do
      nil ->
        nil

      {mod, function, arguments} ->
        normalise_default_locale(apply(mod, function, [subject | arguments]))

      locale ->
        normalise_default_locale(locale)
    end
  end

  defp normalise_default_locale(locale) do
    case Localize.Translate.Locale.normalise(locale) do
      {:ok, locale_id} -> locale_id
      {:error, _exception} -> nil
    end
  end

  defp classify_locale_or_field(%{__struct__: module}, value) do
    if translatable_field?(module, value) do
      {:field, value}
    else
      {:locale, expand_locale(value)}
    end
  end

  defp translatable_field?(module, value) do
    is_atom(value) and not is_nil(value) and not is_boolean(value) and
      Keyword.has_key?(module.__info__(:functions), :__trans__) and
      value in module.__trans__(:fields)
  end

  # `translate/2,3` leave an invalid locale out of the chain, so a locale taken from a
  # request falls through to the next locale or the base value instead of raising.
  defp expand_locale(locale) do
    Localize.Translate.Locale.expand_valid(locale)
  end

  defp expand_locale!(locale) do
    case Localize.Translate.Locale.expand(locale) do
      {:ok, chain} -> chain
      {:error, exception} -> raise exception
    end
  end

  # With `:localize` always present, `current/0` reliably returns a `LanguageTag`.
  # `translate/N` then expands it through the CLDR parent chain, so a missing
  # translation degrades through parents to the schema's `:default_locale` value
  # in the base columns.
  defp default_locale_for(_struct) do
    Localize.Translate.Locale.current()
  end

  # A store whose translations do not travel with the subject populates the
  # container in one call here, so resolution below costs no further I/O. Stores
  # that do not implement the callback — the embedded one — are left alone. A
  # load failure degrades to the unloaded subject and its base values rather
  # than propagating, because `translate/2,3` return values, not tuples.
  defp load_translations(%{__struct__: module} = struct) do
    store = module.__trans__(:store)

    # `Code.ensure_loaded?/1` first: `function_exported?/3` answers false for a
    # module that is compiled but not yet loaded, which would silently skip the
    # load on the first call after boot and return untranslated base values.
    if Code.ensure_loaded?(store) and function_exported?(store, :load_translations, 2) do
      case store.load_translations(struct, module.__trans__(:store_options)) do
        {:ok, loaded} -> loaded
        {:error, _reason} -> struct
      end
    else
      struct
    end
  end

  # The value of a locale is its translation, or the base field for the default locale.
  # A `nil` value counts as missing, so a chain moves on to its next locale; this is the
  # rule `QueryBuilder.translated/4` applies in SQL.
  defp translate_field(%{__struct__: _module} = struct, locales, field, default_locale)
       when is_list(locales) do
    Enum.reduce_while(locales, :error, fn locale, translated_field ->
      case translate_field(struct, locale, field, default_locale) do
        :error -> {:cont, translated_field}
        nil -> {:cont, translated_field}
        translation -> {:halt, translation}
      end
    end)
  end

  defp translate_field(%{__struct__: _module} = struct, default_locale, field, default_locale) do
    Map.fetch!(struct, field)
  end

  defp translate_field(%{__struct__: module} = struct, locale, field, _default_locale) do
    store = module.__trans__(:store)

    case store.fetch_translation(struct, locale, field, module.__trans__(:store_options)) do
      {:ok, nil} -> :error
      {:ok, translated_field} -> translated_field
      :error -> :error
    end
  end

  defp translate_fields(%{__struct__: module} = struct, locale, default_locale) do
    fields = module.__trans__(:fields)

    Enum.reduce(fields, struct, fn field, struct ->
      case translate_field(struct, locale, field, default_locale) do
        :error -> struct
        nil -> struct
        translation -> Map.put(struct, field, translation)
      end
    end)
  end

  # Only a related value that is itself translatable is translated. Anything else (an
  # unloaded marker of any data layer, `nil`, a plain map, a struct that does not use
  # `Localize.Translate`) is left as it is, so no data layer's types need naming here.
  defp translate_assocs(%{__struct__: module} = struct, locale) do
    module.__trans__(:associations)
    |> Enum.filter(&Map.has_key?(struct, &1))
    |> Enum.reduce(struct, fn field, struct ->
      Map.update!(struct, field, &translate_related(&1, locale))
    end)
  end

  defp translate_related(items, locale) when is_list(items) do
    Enum.map(items, &translate_related(&1, locale))
  end

  defp translate_related(%{__struct__: module} = item, locale) do
    if translatable_module?(module) do
      do_translate(item, locale)
    else
      item
    end
  end

  defp translate_related(item, _locale) do
    item
  end

  defp translatable_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__trans__, 1)
  end

  @doc false
  # The default for `__trans__(:associations)`: an Ecto schema's associations and
  # embeds, or none for a module that is not an Ecto schema.
  def __associations__(module) do
    if function_exported?(module, :__schema__, 1) do
      module.__schema__(:associations) ++ module.__schema__(:embeds)
    else
      []
    end
  end

  defp no_translation_error(field, locales) when is_list(locales) do
    "translation doesn't exist for field '#{inspect(field)}' in locales #{inspect(locales)}"
  end

  defp no_translation_error(field, locale) do
    "translation doesn't exist for field '#{inspect(field)}' in locale #{inspect(locale)}"
  end

  defp not_translatable_error(%{__struct__: module}, field) do
    "#{inspect(module)} does not declare #{inspect(field)} as translatable"
  end

  defp not_translatable_error(other, _field) do
    "expected a struct that uses Localize.Translate, got: #{inspect(other)}"
  end

  @doc false
  def __validate_translatable_fields__(%{module: module}, _bytecode) do
    struct_fields = Map.keys(module.__struct__())
    translatable_fields = module.__trans__(:fields)
    invalid_fields = translatable_fields -- struct_fields

    case invalid_fields do
      [] ->
        nil

      [field] ->
        raise ArgumentError,
          message:
            "#{inspect(module)} declares '#{inspect(field)}' as translatable " <>
              "but it is not defined in the module's struct"

      fields ->
        raise ArgumentError,
          message:
            "#{inspect(module)} declares #{inspect(fields)} as translatable " <>
              "but they are not defined in the module's struct"
    end
  end

  # The options of `translations/3,4`, checked as the macro expands. `options`
  # is the quoted keyword list, so its keys are atoms and its values are AST.
  @doc false
  def __validate_trans_options__(module, options) do
    unknown = Keyword.keys(options) -- known_trans_options()

    cond do
      match?([_ | _], unknown) ->
        raise ArgumentError,
          message:
            "#{inspect(module)} gives translations the unknown options #{inspect(unknown)}. " <>
              "The options are #{inspect(known_trans_options())}"

      Keyword.has_key?(options, :fields_module) and options[:build_field_schema] == false ->
        raise ArgumentError,
          message:
            "#{inspect(module)} gives translations both :fields_module and " <>
              "build_field_schema: false. With build_field_schema: false no schema is " <>
              "generated, so name the fields schema in a translation schema of your own"

      true ->
        :ok
    end
  end

  # A caller's per-locale schema must be a compiled Ecto schema that defines
  # every translatable field as a string, since translations are read from it
  # by name and queried as text.
  @doc false
  def __validate_fields_module__(module, fields_module, fields) do
    cond do
      not compiled_module?(fields_module) ->
        raise ArgumentError,
          message:
            "#{inspect(module)} names #{inspect(fields_module)} as its :fields_module, " <>
              "but it is not a compiled module. Define it before #{inspect(module)}, " <>
              "not nested inside it"

      not function_exported?(fields_module, :__schema__, 2) ->
        raise ArgumentError,
          message:
            "#{inspect(module)} names #{inspect(fields_module)} as its :fields_module, " <>
              "but it is not an Ecto schema"

      true ->
        validate_fields_module_fields(module, fields_module, fields)
    end
  end

  defp compiled_module?(module) when is_atom(module) do
    match?({:module, _module}, Code.ensure_compiled(module))
  end

  defp compiled_module?(_other) do
    false
  end

  defp validate_fields_module_fields(module, fields_module, fields) do
    missing = fields -- fields_module.__schema__(:fields)
    defined = fields -- missing
    not_strings = Enum.reject(defined, &(fields_module.__schema__(:type, &1) == :string))

    cond do
      match?([_ | _], missing) ->
        raise ArgumentError,
          message:
            "#{inspect(fields_module)} must define the translatable fields " <>
              "#{inspect(missing)} of #{inspect(module)}"

      match?([_ | _], not_strings) ->
        raise ArgumentError,
          message:
            "#{inspect(fields_module)} must define the translatable fields " <>
              "#{inspect(not_strings)} of #{inspect(module)} as :string"

      true ->
        :ok
    end
  end

  @doc false
  def __validate_translation_container__(%{module: module}, _bytecode) do
    container = module.__trans__(:container)

    unless Enum.member?(Map.keys(module.__struct__()), container) do
      raise ArgumentError,
        message:
          "The field #{container} used as the translation container is not defined in #{inspect(module)} struct"
    end
  end

  @doc false
  def trans_fields(options) do
    case Keyword.fetch(options, :translates) do
      {:ok, fields} when is_list(fields) ->
        fields

      _ ->
        raise ArgumentError,
          message:
            "Localize.Translate requires a 'translates' option that contains the list of translatable field names"
    end
  end

  @doc false
  def trans_store(options) do
    case Keyword.fetch(options, :store) do
      :error -> Localize.Translate.Store.Embedded
      {:ok, {store, _store_options}} -> store
      {:ok, store} -> store
    end
  end

  @doc false
  def trans_store_options(options) do
    case Keyword.fetch(options, :store) do
      {:ok, {_store, store_options}} -> store_options
      _other -> []
    end
  end

  @doc false
  def trans_container(options) do
    case Keyword.fetch(options, :container) do
      :error -> :translations
      {:ok, container} -> container
    end
  end

  @doc false
  def trans_locales(options) do
    case Keyword.fetch(options, :locales) do
      :error ->
        nil

      {:ok, locales} ->
        locales
        |> Enum.map(&Localize.Translate.Locale.normalise!/1)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  @doc false
  def trans_default_locale(options) do
    case Keyword.fetch(options, :default_locale) do
      :error ->
        nil

      {:ok, {module, function, arguments} = mfa}
      when is_atom(module) and is_atom(function) and is_list(arguments) ->
        mfa

      {:ok, default_locale} when is_atom(default_locale) or is_binary(default_locale) ->
        default_locale

      {:ok, other} ->
        raise ArgumentError,
          message:
            "Localize.Translate :default_locale must be a locale or a {module, function, arguments} tuple, got: #{inspect(other)}"
    end
  end

  @doc false
  def trans_module(nil) do
    {:__aliases__, [], [:Translations]}
  end

  def trans_module(translation_module) do
    translation_module
  end
end
