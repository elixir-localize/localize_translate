defmodule Localize.Translate.LocaleChainTest do
  use ExUnit.Case, async: true

  alias Localize.Translate
  alias Localize.Translate.{Article, QueryBuilder}

  describe "locale_id/1" do
    test "returns the canonical CLDR locale id for an atom, a string or a tag" do
      {:ok, tag} = Localize.LanguageTag.new("es-419")

      assert Translate.locale_id("fr_CA") == {:ok, :"fr-CA"}
      assert Translate.locale_id(:"fr-CA") == {:ok, :"fr-CA"}
      assert Translate.locale_id(tag) == {:ok, :"es-419"}
    end

    test "folds a language's default region into the language" do
      assert Translate.locale_id("en-US") == {:ok, :en}
      assert Translate.locale_id("es_ES") == {:ok, :es}
    end

    test "refuses a value that is not a locale" do
      for value <- [nil, "", :"", 42, %{}, "not a locale", [:en]] do
        assert {:error, %Localize.InvalidLocaleError{}} = Translate.locale_id(value),
               inspect(value)
      end
    end

    test "refuses a language CLDR has no data for, which would resolve to und" do
      for value <- ["tlh", "qaa", "und", :und] do
        assert {:error, %Localize.InvalidLocaleError{}} = Translate.locale_id(value),
               inspect(value)
      end
    end
  end

  describe "locale_chain/2 and the CLDR root" do
    test "leaves out a locale that resolves to und" do
      assert Translate.locale_chain("tlh") == []
      assert Translate.locale_chain(["tlh", :es]) == [:es]
      assert Translate.locale_chain(:und) == []
    end
  end

  describe "locale_chain/2" do
    test "walks the CLDR parent chain of a locale given as an atom, a string or a tag" do
      {:ok, tag} = Localize.LanguageTag.new("es-419")

      assert Translate.locale_chain(:"fr-CA") == [:"fr-CA", :fr]
      assert Translate.locale_chain("fr-CA") == [:"fr-CA", :fr]
      assert Translate.locale_chain(tag) == [:"es-419", :es]
    end

    test "expands a list in order and removes duplicates" do
      assert Translate.locale_chain([:"fr-CA", :fr, :es, :"es-419"]) == [
               :"fr-CA",
               :fr,
               :es,
               :"es-419"
             ]
    end

    test "leaves out locales that are not valid" do
      assert Translate.locale_chain([nil, "", "not a locale", 42, %{}, :es]) == [:es]
    end

    test "is empty when no locale is valid" do
      for value <- [nil, [], "", :"", 42, "not a locale", [nil]] do
        assert Translate.locale_chain(value) == [], inspect(value)
      end
    end

    test "filters the chain to the supported locales" do
      assert Translate.locale_chain(:"en-AU", supported: [:en, :es]) == [:en]
      assert Translate.locale_chain([:de, :es], supported: Article.__trans__(:locales)) == [:es]
    end

    test "keeps the whole chain when :supported is nil, empty or not a list" do
      for options <- [[], [supported: nil], [supported: []], [supported: :en], nil, :bad] do
        assert Translate.locale_chain(:"fr-CA", options) == [:"fr-CA", :fr], inspect(options)
      end
    end

    test "is the chain the query builder sends to SQL" do
      supported = Article.__trans__(:locales)

      for locale <- [:"es-419", [:de, :es], "fr-CA", "not a locale", nil] do
        expected = QueryBuilder.list_to_sql_array(locale, supported)
        chain = Translate.locale_chain(locale, supported: supported)

        assert Enum.map(chain, &Atom.to_string/1) == expected, inspect(locale)
      end
    end
  end
end
