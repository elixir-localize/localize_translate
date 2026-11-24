defmodule Localize.Translate.Store.SiblingResourceTest.MissingTable do
  @moduledoc false

  # A sibling schema whose table does not exist, so the query fails in the database.
  use Ecto.Schema

  schema "no_such_page_translations" do
    field(:locale, :string)
    field(:title, :string)
    field(:body, :string)
    field(:page_id, :integer)
  end
end

defmodule Localize.Translate.Store.SiblingResourceTest do
  use Localize.Translate.TestCase, async: false

  alias Localize.Translate
  alias Localize.Translate.Page
  alias Localize.Translate.PageTranslation
  alias Localize.Translate.Store.SiblingResource

  setup do
    page = Repo.insert!(%Page{title: "English title", body: "English body"})

    Repo.insert!(%PageTranslation{
      page_id: page.id,
      locale: "es",
      title: "Título",
      body: "Cuerpo"
    })

    Repo.insert!(%PageTranslation{page_id: page.id, locale: "fr", title: "Titre", body: nil})

    [page: page]
  end

  describe "queryable?/0" do
    test "reports that predicates cannot be pushed into the data layer" do
      refute SiblingResource.queryable?()
    end
  end

  describe "load_translations/2" do
    test "reshapes sibling rows into the container map", %{page: page} do
      {:ok, loaded} = SiblingResource.load_translations(page, store_options())

      assert loaded.translations["es"]["title"] == "Título"
      assert loaded.translations["fr"]["title"] == "Titre"
    end

    test "presents an empty container for an unpersisted subject" do
      {:ok, loaded} = SiblingResource.load_translations(%Page{title: "New"}, store_options())

      assert loaded.translations == %{}
    end

    test "returns an error tuple rather than raising when options are missing",
         %{page: page} do
      assert {:error, %ArgumentError{}} = SiblingResource.load_translations(page, [])
    end

    test "returns an error tuple for each misconfigured option", %{page: page} do
      misconfigured = [
        Keyword.put(store_options(), :repo, NotARepo),
        Keyword.put(store_options(), :repo, "Repo"),
        Keyword.put(store_options(), :schema, URI),
        Keyword.put(store_options(), :schema, nil),
        Keyword.put(store_options(), :foreign_key, :article_id),
        Keyword.put(store_options(), :locale_field, :language),
        Keyword.put(store_options(), :primary_key, :uuid)
      ]

      for options <- misconfigured do
        assert {:error, %ArgumentError{message: message}} =
                 SiblingResource.load_translations(page, options)

        assert message =~ "SiblingResource", inspect(options)
      end
    end

    test "returns an error tuple when the options are not a keyword list", %{page: page} do
      for options <- [nil, %{}, "options"] do
        assert {:error, %ArgumentError{}} = SiblingResource.load_translations(page, options)
      end
    end

    test "returns the database error rather than raising", %{page: page} do
      options = Keyword.put(store_options(), :schema, __MODULE__.MissingTable)

      assert {:error, %Postgrex.Error{}} = SiblingResource.load_translations(page, options)
    end
  end

  describe "translate/3 through the store" do
    test "resolves a field from the sibling table", %{page: page} do
      assert Translate.translate(page, :title, :es) == "Título"
    end

    test "falls back to the base value for a locale with no row" do
      page = Repo.insert!(%Page{title: "Only English"})

      assert Translate.translate(page, :title, :es) == "Only English"
    end

    test "falls back to the base value for a nil column", %{page: page} do
      assert Translate.translate(page, :body, :fr) == "English body"
    end

    test "walks a fallback chain across locales", %{page: page} do
      assert Translate.translate(page, :title, [:de, :fr]) == "Titre"
    end
  end

  describe "translate!/3 through the store" do
    test "loads the sibling rows before resolving", %{page: page} do
      assert Translate.translate!(page, :title, :es) == "Título"
    end

    test "raises when no sibling row has the locale", %{page: page} do
      assert_raise RuntimeError, ~r/translation doesn't exist/, fn ->
        Translate.translate!(page, :title, :de)
      end
    end
  end

  describe "translate/2 through the store" do
    test "translates every field of the struct", %{page: page} do
      translated = Translate.translate(page, :es)

      assert translated.title == "Título"
      assert translated.body == "Cuerpo"
    end

    test "loads translations exactly once for the whole struct", %{page: page} do
      # Two fields over a two-locale chain would be four queries without the
      # load hook; with it, the container is populated once up front.
      {:ok, loaded} = SiblingResource.load_translations(page, store_options())

      assert map_size(loaded.translations) == 2
    end
  end

  describe "locales/2" do
    test "lists the locales present in the sibling table", %{page: page} do
      {:ok, loaded} = SiblingResource.load_translations(page, store_options())

      assert Enum.sort(SiblingResource.locales(loaded, [])) == [:es, :fr]
    end
  end

  describe "default arguments" do
    test "options may be omitted on fetch_translation/3", %{page: page} do
      {:ok, loaded} = SiblingResource.load_translations(page, store_options())

      assert SiblingResource.fetch_translation(loaded, :es, :title) == {:ok, "Título"}
    end

    test "options may be omitted on locales/1", %{page: page} do
      {:ok, loaded} = SiblingResource.load_translations(page, store_options())

      assert Enum.sort(SiblingResource.locales(loaded)) == [:es, :fr]
    end
  end

  describe "store configuration" do
    test "the schema reports the store and its options" do
      assert Page.__trans__(:store) == SiblingResource
      assert Page.__trans__(:store_options)[:repo] == Localize.Translate.Repo
      assert Page.__trans__(:store_options)[:schema] == PageTranslation
    end
  end

  defp store_options do
    Page.__trans__(:store_options)
  end
end
