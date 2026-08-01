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
    repo = fetch_option!(options, :repo)
    schema = fetch_option!(options, :schema)
    foreign_key = fetch_option!(options, :foreign_key)
    locale_field = Keyword.get(options, :locale_field, :locale)
    primary_key = Keyword.get(options, :primary_key, :id)

    case Map.fetch!(subject, primary_key) do
      nil ->
        # An unpersisted subject has no rows to load. Present an empty container
        # so resolution falls back to base values rather than raising.
        {:ok, put_container(subject, module, %{})}

      id ->
        rows = repo.all(from(t in schema, where: field(t, ^foreign_key) == ^id))
        fields = module.__trans__(:fields)

        {:ok, put_container(subject, module, build_container(rows, fields, locale_field))}
    end
  rescue
    exception -> {:error, exception}
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
  def queryable?, do: false

  # Reshape the sibling rows into the container map the embedded store reads.
  defp build_container(rows, fields, locale_field) do
    Map.new(rows, fn row ->
      values = Map.new(fields, fn field -> {to_string(field), Map.get(row, field)} end)

      {to_string(Map.fetch!(row, locale_field)), values}
    end)
  end

  defp put_container(subject, module, container) do
    Map.put(subject, module.__trans__(:container), container)
  end

  defp fetch_option!(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} requires a #{inspect(key)} option, " <>
                "given: #{inspect(options)}"
    end
  end
end
