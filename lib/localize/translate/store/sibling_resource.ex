defmodule Localize.Translate.Store.SiblingResource do
  @moduledoc """
  A translation store keeping translations in a sibling table, one row per
  `(subject, locale)`.

  This is the traditional relational model — `posts` and `posts_translations` —
  which `Localize.Translate.Store.Embedded` exists to avoid. It is offered
  because the embedded model cannot do some things a translation workflow needs:

  * **Per-translation state.** A `status`, a reviewer, a timestamp, or any other
    column that belongs to one locale's translation rather than to the record.

  * **Per-locale permissions.** A translator who may edit `fr` but not `de`.

  * **Translation history.** Row-level auditing tools track a sibling row; they
    cannot track one locale inside a `jsonb` column.

  * **Concurrent editing.** Two translators working on different locales write
    different rows rather than contending on one column.

  If none of those apply, use the embedded store. It is simpler, needs no join,
  and is the default.

  ## The sibling schema

  You define it — this store does not generate one. It needs a foreign key to
  the subject, a `locale` column, and one column per translatable field:

      defmodule MyApp.ArticleTranslation do
        use Ecto.Schema

        schema "article_translations" do
          field(:locale, :string)
          field(:title, :string)
          field(:body, :string)
          belongs_to(:article, MyApp.Article)
        end
      end

  A unique index on `(article_id, locale)` is strongly advised; without one,
  nothing stops two rows claiming the same translation.

  ## Declaring it

  The subject needs a **virtual** container field for loaded translations to
  live in, and the store needs to know the repo, the sibling schema, and the
  foreign key:

      defmodule MyApp.Article do
        use Ecto.Schema

        use Localize.Translate,
          translates: [:title, :body],
          locales: [:en, :es, :fr],
          default_locale: :en,
          store:
            {Localize.Translate.Store.SiblingResource,
             repo: MyApp.Repo,
             schema: MyApp.ArticleTranslation,
             foreign_key: :article_id}

        schema "articles" do
          field(:title, :string)
          field(:body, :string)
          field(:translations, :map, virtual: true)
        end
      end

  ## How resolution works

  `c:Localize.Translate.Store.load_translations/2` fetches every translation row
  for the subject in **one query** and reshapes them into the same
  `%{locale => %{field => value}}` map the embedded store uses, placing it in
  the virtual container. `Localize.Translate` calls it once at the start of
  `translate/2,3`, so resolving several fields across a CLDR fallback chain
  costs that single query rather than one per field per candidate locale.

  Reads therefore delegate to the embedded store, which already knows how to
  answer from that shape.

  ## Options

  * `:repo` — the `Ecto.Repo` to query. Required.

  * `:schema` — the sibling `Ecto.Schema` module. Required.

  * `:foreign_key` — the column on the sibling schema pointing at the subject.
    Required.

  * `:locale_field` — the column holding the locale. Defaults to `:locale`.

  * `:primary_key` — the field on the subject the foreign key points at.
    Defaults to `:id`.

  """

  @behaviour Localize.Translate.Store

  alias Localize.Translate.Store.Embedded

  import Ecto.Query, only: [from: 2]

  @impl Localize.Translate.Store
  def load_translations(%{__struct__: module} = subject, options) do
    with {:ok, configuration} <- configuration(subject, options),
         {:ok, rows} <- fetch_rows(configuration) do
      fields = module.__trans__(:fields)
      container = build_container(rows, fields, configuration.locale_field)

      {:ok, put_container(subject, module, container)}
    end
  end

  @impl Localize.Translate.Store
  def fetch_translation(subject, locale, field, options \\ []) do
    Embedded.fetch_translation(subject, locale, field, options)
  end

  @impl Localize.Translate.Store
  def locales(subject, options \\ []) do
    Embedded.locales(subject, options)
  end

  @impl Localize.Translate.Store
  def queryable?(_schema) do
    false
  end

  # Every option and the subject's key are checked before the query, so a
  # misconfiguration is an error tuple rather than an exception.
  defp configuration(subject, options) when is_list(options) do
    locale_field = Keyword.get(options, :locale_field, :locale)
    primary_key = Keyword.get(options, :primary_key, :id)

    with {:ok, repo} <- required_option(options, :repo),
         {:ok, schema} <- required_option(options, :schema),
         {:ok, foreign_key} <- required_option(options, :foreign_key),
         :ok <- validate_repo(repo),
         {:ok, schema_fields} <- schema_fields(schema),
         :ok <- validate_field(schema, schema_fields, foreign_key, :foreign_key),
         :ok <- validate_field(schema, schema_fields, locale_field, :locale_field),
         {:ok, id} <- primary_key_value(subject, primary_key) do
      {:ok,
       %{
         repo: repo,
         schema: schema,
         foreign_key: foreign_key,
         locale_field: locale_field,
         id: id
       }}
    end
  end

  defp configuration(_subject, options) do
    configuration_error("options must be a keyword list, given: #{inspect(options)}")
  end

  defp required_option(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        configuration_error("requires a #{inspect(key)} option, given: #{inspect(options)}")
    end
  end

  defp validate_repo(repo) do
    if is_atom(repo) and Code.ensure_loaded?(repo) and function_exported?(repo, :all, 2) do
      :ok
    else
      configuration_error("the :repo option must be an Ecto.Repo, given: #{inspect(repo)}")
    end
  end

  defp schema_fields(schema) do
    if is_atom(schema) and Code.ensure_loaded?(schema) and
         function_exported?(schema, :__schema__, 1) do
      {:ok, schema.__schema__(:fields)}
    else
      configuration_error("the :schema option must be an Ecto schema, given: #{inspect(schema)}")
    end
  end

  defp validate_field(schema, schema_fields, field, option) do
    if field in schema_fields do
      :ok
    else
      configuration_error(
        "the #{inspect(option)} option names #{inspect(field)}, which #{inspect(schema)} does not define"
      )
    end
  end

  defp primary_key_value(subject, primary_key) do
    case Map.fetch(subject, primary_key) do
      {:ok, id} ->
        {:ok, id}

      :error ->
        configuration_error(
          "the :primary_key option names #{inspect(primary_key)}, which #{inspect(subject.__struct__)} does not define"
        )
    end
  end

  defp configuration_error(message) do
    {:error, ArgumentError.exception("#{inspect(__MODULE__)} #{message}")}
  end

  # An unpersisted subject has no rows to load. Present an empty container so
  # resolution falls back to base values rather than querying.
  defp fetch_rows(%{id: nil}) do
    {:ok, []}
  end

  # The repo call is the system boundary: Ecto has no non-raising form of
  # `Repo.all/2`, and a database error must not crash `translate/2,3`, which fall
  # back to base values when loading fails.
  defp fetch_rows(%{repo: repo, schema: schema, foreign_key: foreign_key, id: id}) do
    {:ok, repo.all(from(t in schema, where: field(t, ^foreign_key) == ^id))}
  rescue
    exception -> {:error, exception}
  end

  # Reshape the sibling rows into the container map the embedded store reads.
  # A row with no locale is left out.
  defp build_container(rows, fields, locale_field) do
    for row <- rows, locale = Map.get(row, locale_field), not is_nil(locale), into: %{} do
      values = Map.new(fields, fn field -> {Atom.to_string(field), Map.get(row, field)} end)

      {to_string(locale), values}
    end
  end

  defp put_container(subject, module, container) do
    Map.put(subject, module.__trans__(:container), container)
  end
end
