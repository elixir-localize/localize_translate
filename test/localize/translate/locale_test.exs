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

    test "raises on a language CLDR has no data for" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Locale.normalise!(:tlh)
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
      assert Locale.expand(:es) == {:ok, [:es]}
    end

    test "string expands to a single-element chain" do
      assert Locale.expand("es") == {:ok, [:es]}
    end

    test "list expands per-element with dedup" do
      assert Locale.expand([:en, :fr, :en]) == {:ok, [:en, :fr]}
    end

    test "returns an error for nil" do
      assert {:error, %Localize.InvalidLocaleError{}} = Locale.expand(nil)
    end

    test "LanguageTag walks the CLDR parent chain" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand(tag) == {:ok, [:"en-AU", :"en-001", :en]}
    end

    test "omits :und root" do
      {:ok, tag} = Localize.LanguageTag.new("en")
      {:ok, chain} = Locale.expand(tag)
      assert :und not in chain
      assert :en in chain
    end

    test "flattens and dedupes mixed lists" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand([:fr, tag, :en]) == {:ok, [:fr, :"en-AU", :"en-001", :en]}
    end

    test "returns an error for an invalid locale in a list" do
      assert {:error, %Localize.InvalidLocaleError{}} = Locale.expand([:en, :xyzabc])
    end

    test "returns an error for nil inside a list" do
      assert {:error, %Localize.InvalidLocaleError{}} = Locale.expand([:en, nil])
    end

    test "returns an error for values that are not locales" do
      for value <- ["", :"", 42, %{}, {:en}, "en-" <> String.duplicate("x", 300)] do
        assert {:error, %{__exception__: true}} = Locale.expand(value), inspect(value)
      end
    end
  end

  describe "expand/2 with supported filter" do
    test "nil supported is a no-op filter" do
      assert Locale.expand([:en, :fr], nil) == {:ok, [:en, :fr]}
    end

    test "empty supported is a no-op filter" do
      assert Locale.expand([:en, :fr], []) == {:ok, [:en, :fr]}
    end

    test "filters to supported" do
      assert Locale.expand([:en, :fr, :de], [:en, :fr]) == {:ok, [:en, :fr]}
    end

    test "filters the walked chain to supported locales" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand(tag, [:en, :fr]) == {:ok, [:en]}
    end
  end

  describe "expand_valid/1,2" do
    test "expands valid locales as expand/2 does" do
      {:ok, tag} = Localize.LanguageTag.new("en-AU")
      assert Locale.expand_valid([:fr, tag]) == [:fr, :"en-AU", :"en-001", :en]
    end

    test "leaves out invalid locales and keeps the rest in order" do
      assert Locale.expand_valid([:xyzabc, :es, nil, "", 42, :fr]) == [:es, :fr]
    end

    test "returns an empty chain when no locale is valid" do
      for value <- [nil, :xyzabc, "", :"", 42, %{}, [nil, "not a locale"]] do
        assert Locale.expand_valid(value) == [], inspect(value)
      end
    end

    test "filters to supported locales" do
      assert Locale.expand_valid([:xyzabc, :en, :de], [:en]) == [:en]
    end
  end
end
