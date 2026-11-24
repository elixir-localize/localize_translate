defmodule Localize.Translate.ValidateTranslationsTest.Sites do
  @moduledoc false

  def default_locale(%{site_locale: locale}) do
    locale
  end

  def default_locale(nil) do
    nil
  end
end

defmodule Localize.Translate.ValidateTranslationsTest.SiteNote do
  @moduledoc false
  use Ecto.Schema

  use Localize.Translate,
    translates: [:title],
    default_locale: {Localize.Translate.ValidateTranslationsTest.Sites, :default_locale, []}

  embedded_schema do
    field(:title, :string)
    field(:site_locale, :string)
    field(:translations, :map, default: %{})
  end
end

defmodule Localize.Translate.ValidateTranslationsTest.SiteArticle do
  @moduledoc false
  use Ecto.Schema

  use Localize.Translate,
    translates: [:title],
    locales: [:en, :fr],
    default_locale: {Localize.Translate.ValidateTranslationsTest.Sites, :default_locale, []}

  embedded_schema do
    field(:title, :string)
    field(:site_locale, :string)
    translations(:translations)
  end
end

defmodule Localize.Translate.ValidateTranslationsTest.LiteralNote do
  @moduledoc false
  use Ecto.Schema

  use Localize.Translate, translates: [:title], locales: [:en, :es, :fr], default_locale: :en

  embedded_schema do
    field(:title, :string)
    field(:translations, :map, default: %{})
  end
end

defmodule Localize.Translate.ValidateTranslationsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias Localize.Translate
  alias Localize.Translate.ValidateTranslationsTest.{LiteralNote, SiteArticle, SiteNote}

  defp translations_error(changeset) do
    case Keyword.get(changeset.errors, :translations) do
      {message, _details} -> message
      nil -> nil
    end
  end

  describe "a map container with a function default" do
    test "refuses the record's own default locale and accepts the others" do
      french = %SiteNote{site_locale: "fr"}

      refused =
        french
        |> change(translations: %{"fr" => %{"title" => "Bonjour"}})
        |> Translate.validate_translations()

      accepted =
        french
        |> change(translations: %{"en" => %{"title" => "Hello"}})
        |> Translate.validate_translations()

      assert translations_error(refused) =~ "fr, the default locale"
      refute refused.valid?
      assert accepted.valid?
    end

    test "resolves the default from the record as the change leaves it" do
      record = %SiteNote{site_locale: "fr", translations: %{"en" => %{"title" => "Hello"}}}

      changeset = record |> change(site_locale: "en") |> Translate.validate_translations()

      assert translations_error(changeset) =~ "en, the default locale"
    end

    test "does not count an entry with no values" do
      changeset =
        %SiteNote{site_locale: "fr"}
        |> change(translations: %{"fr" => %{"title" => nil}})
        |> Translate.validate_translations()

      assert changeset.valid?
    end

    test "leaves an unrelated update to a row that already breaks the rule alone" do
      record = %SiteNote{site_locale: "fr", translations: %{"fr" => %{"title" => "Bonjour"}}}

      changeset = record |> change(title: "Salut") |> Translate.validate_translations()

      assert changeset.valid?
    end
  end

  describe "generated embeds with a function default" do
    test "refuses text in the default locale's embed" do
      french = %SiteArticle{site_locale: "fr"}

      refused =
        french
        |> change()
        |> put_embed(:translations, %SiteArticle.Translations{
          fr: %SiteArticle.Translations.Fields{title: "Bonjour"}
        })
        |> Translate.validate_translations()

      accepted =
        french
        |> change()
        |> put_embed(:translations, %SiteArticle.Translations{
          en: %SiteArticle.Translations.Fields{title: "Hello"}
        })
        |> Translate.validate_translations()

      assert translations_error(refused) =~ "fr, the default locale"
      assert accepted.valid?
    end
  end

  describe "a map container with a literal default and locales" do
    test "refuses the default locale, a locale outside the list and an invalid key" do
      check = fn translations ->
        %LiteralNote{}
        |> change(translations: translations)
        |> Translate.validate_translations()
        |> translations_error()
      end

      assert check.(%{"en" => %{"title" => "Hello"}}) =~ "default locale"
      assert check.(%{"de" => %{"title" => "Hallo"}}) =~ "not one of the schema's locales"
      assert check.(%{"not a locale" => %{"title" => "x"}}) =~ "not a valid locale"
      assert is_nil(check.(%{"es" => %{"title" => "Hola"}, "fr_CA" => %{"title" => nil}}))
    end
  end

  describe "other changesets" do
    test "a schema that does not use Localize.Translate is returned unchanged" do
      changeset = Ecto.Changeset.change(%Localize.Translate.PageTranslation{}, locale: "es")
      schemaless = Ecto.Changeset.cast({%{}, %{title: :string}}, %{"title" => "x"}, [:title])

      assert Translate.validate_translations(changeset) == changeset
      assert Translate.validate_translations(schemaless) == schemaless
      assert Translate.validate_translations(:not_a_changeset) == :not_a_changeset
    end
  end
end
