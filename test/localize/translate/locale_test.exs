defmodule Localize.Translate.LocaleTest do
  use ExUnit.Case, async: true

  alias Localize.Translate.Locale

  describe "normalise!/1" do
    test "atom passthrough" do
      assert Locale.normalise!(:en) == :en
    end

    test "string canonicalises to atom" do
      assert Locale.normalise!("en") == :en
    end

    test "LanguageTag unwraps to cldr_locale_id" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.normalise!(tag) == :"en-AU"
    end

    test "raises on invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Locale.normalise!(:xyzabc)
      end
    end
  end

  describe "current/0" do
    test "returns the current Localize locale as a LanguageTag" do
      assert %Localize.LanguageTag{} = Locale.current()
    end
  end

  describe "expand/1" do
    test "atom expands to a single-element chain" do
      assert Locale.expand(:es) == [:es]
    end

    test "string expands to a single-element chain" do
      assert Locale.expand("es") == [:es]
    end

    test "list expands per-element with dedup" do
      assert Locale.expand([:en, :fr, :en]) == [:en, :fr]
    end

    test "nil expands to empty" do
      assert Locale.expand(nil) == []
    end

    test "LanguageTag walks the CLDR parent chain" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand(tag) == [:"en-AU", :"en-001", :en]
    end

    test "omits :und root" do
      {:ok, tag} = Localize.LanguageTag.new("en")
      chain = Locale.expand(tag)
      assert :und not in chain
      assert :en in chain
    end

    test "flattens and dedupes mixed lists" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand([:fr, tag, :en]) == [:fr, :"en-AU", :"en-001", :en]
    end

    test "raises on invalid locale in a list" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Locale.expand([:en, :xyzabc])
      end
    end
  end

  describe "expand/2 with supported filter" do
    test "nil supported is a no-op filter" do
      assert Locale.expand([:en, :fr], nil) == [:en, :fr]
    end

    test "empty supported is a no-op filter" do
      assert Locale.expand([:en, :fr], []) == [:en, :fr]
    end

    test "filters to supported" do
      assert Locale.expand([:en, :fr, :de], [:en, :fr]) == [:en, :fr]
    end

    test "filters the walked chain to supported locales" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand(tag, [:en, :fr]) == [:en]
    end
  end
end
