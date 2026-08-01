defmodule Localize.Translate.TranslationsMacroTest do
  @moduledoc """
  Covers the `translations/1,2,3` macro, which generates the container embed and
  the `Translations` / `Translations.Fields` schemas from the declared locales
  and translatable fields.

  """

  use Localize.Translate.TestCase, async: true

  alias Localize.Translate
  alias Localize.Translate.Leaflet

  describe "generated schemas" do
    test "generates the Translations module named after the default" do
      assert Code.ensure_loaded?(Leaflet.Translations)
    end

    test "generates the inner Fields module" do
      assert Code.ensure_loaded?(Leaflet.Translations.Fields)
    end

    test "the Fields schema carries every translatable field" do
      fields = Leaflet.Translations.Fields.__schema__(:fields)

      assert :title in fields
      assert :body in fields
    end

    test "the Translations schema carries one embed per non-default locale" do
      embeds = Leaflet.Translations.__schema__(:embeds)

      assert :es in embeds
      assert :fr in embeds
      refute :en in embeds
    end

    test "the container is declared as an embed on the parent schema" do
      assert :translations in Leaflet.__schema__(:embeds)
    end
  end

  describe "reflection on a macro-declared schema" do
    test "reports the same metadata as an explicitly-declared one" do
      assert Leaflet.__trans__(:fields) == [:title, :body]
      assert Leaflet.__trans__(:container) == :translations
      assert Leaflet.__trans__(:locales) == [:en, :es, :fr]
      assert Leaflet.__trans__(:default_locale) == :en
    end
  end

  describe "translating a macro-declared schema" do
    setup do
      leaflet = %Leaflet{
        title: "English title",
        body: "English body",
        translations: %Leaflet.Translations{
          es: %Leaflet.Translations.Fields{title: "Título", body: "Cuerpo"}
        }
      }

      [leaflet: leaflet]
    end

    test "translates a single field", %{leaflet: leaflet} do
      assert Translate.translate(leaflet, :title, :es) == "Título"
    end

    test "translates the whole struct", %{leaflet: leaflet} do
      translated = Translate.translate(leaflet, :es)

      assert translated.title == "Título"
      assert translated.body == "Cuerpo"
    end

    test "falls back to the base value for a locale with no translation",
         %{leaflet: leaflet} do
      assert Translate.translate(leaflet, :title, :fr) == "English title"
    end

    test "returns the base value for the default locale", %{leaflet: leaflet} do
      assert Translate.translate(leaflet, :title, :en) == "English title"
    end
  end
end
