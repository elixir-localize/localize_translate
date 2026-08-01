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
  end

  describe "translate/3 through the store" do
    test "resolves a field from the sibling table", %{page: page} do
      assert Translate.translate(page, :title, :es) == "Título"
    end

    test "falls back to the base value for a locale with no row", %{page: page} do
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

  defp store_options, do: Page.__trans__(:store_options)
end
