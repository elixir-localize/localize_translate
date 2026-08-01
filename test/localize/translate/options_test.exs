defmodule Localize.Translate.OptionsTest do
  @moduledoc """
  Covers the option readers the `use Localize.Translate` macro calls at compile
  time, and the reflection functions it generates.

  """

  use ExUnit.Case, async: true

  alias Localize.Translate
  alias Localize.Translate.Article
  alias Localize.Translate.Comment
  alias Localize.Translate.Store.Embedded

  describe "trans_fields/1" do
    test "returns the declared translatable fields" do
      assert Translate.trans_fields(translates: [:title, :body]) == [:title, :body]
    end

    test "raises when :translates is absent" do
      assert_raise ArgumentError, ~r/requires a 'translates' option/, fn ->
        Translate.trans_fields([])
      end
    end

    test "raises when :translates is not a list" do
      assert_raise ArgumentError, ~r/requires a 'translates' option/, fn ->
        Translate.trans_fields(translates: :title)
      end
    end
  end

  describe "trans_container/1" do
    test "defaults to :translations" do
      assert Translate.trans_container([]) == :translations
    end

    test "returns an explicit container" do
      assert Translate.trans_container(container: :transcriptions) == :transcriptions
    end
  end

  describe "trans_store/1" do
    test "defaults to the embedded store" do
      assert Translate.trans_store([]) == Embedded
    end

    test "returns an explicit store" do
      defmodule CustomStore do
        @moduledoc false
        @behaviour Localize.Translate.Store

        @impl true
        def fetch_translation(_subject, _locale, _field, _options), do: :error

        @impl true
        def locales(_subject, _options), do: []

        @impl true
        def queryable?, do: false
      end

      assert Translate.trans_store(store: CustomStore) == CustomStore
    end
  end

  describe "trans_locales/1" do
    test "returns nil when no locales are declared" do
      assert Translate.trans_locales([]) == nil
    end

    test "normalises, deduplicates and sorts declared locales" do
      assert Translate.trans_locales(locales: [:fr, :es, :fr]) == [:es, :fr]
    end

    test "accepts locales given as strings" do
      assert Translate.trans_locales(locales: ["es", "fr"]) == [:es, :fr]
    end

    test "raises for a locale CLDR does not recognise" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Translate.trans_locales(locales: [:definitely_not_a_locale])
      end
    end
  end

  describe "trans_default_locale/1" do
    test "returns nil when none is declared" do
      assert Translate.trans_default_locale([]) == nil
    end

    test "returns the declared default locale" do
      assert Translate.trans_default_locale(default_locale: :en) == :en
    end
  end

  describe "trans_module/1" do
    test "defaults to a Translations alias" do
      assert Translate.trans_module(nil) == {:__aliases__, [], [:Translations]}
    end

    test "returns an explicit module unchanged" do
      assert Translate.trans_module(MyApp.Custom) == MyApp.Custom
    end
  end

  describe "default_trans_options/0" do
    test "builds the field schema by default" do
      assert Translate.default_trans_options()[:build_field_schema] == true
    end
  end

  describe "__trans__/1 reflection" do
    test "reports the translatable fields" do
      assert Article.__trans__(:fields) == [:title, :body]
    end

    test "reports the container, which is configurable per schema" do
      assert Article.__trans__(:container) == :translations
      assert Comment.__trans__(:container) == :transcriptions
    end

    test "reports the declared locales, normalised and sorted" do
      assert Article.__trans__(:locales) == [:en, :es, :fr]
    end

    test "reports the default locale" do
      assert Article.__trans__(:default_locale) == :en
    end

    test "reports the store" do
      assert Article.__trans__(:store) == Embedded
    end
  end

  describe "translatable?/2" do
    test "is true for a declared field, given the module" do
      assert Translate.translatable?(Article, :title)
    end

    test "is true for a declared field, given a struct" do
      assert Translate.translatable?(%Article{}, :title)
    end

    test "accepts the field as a string" do
      assert Translate.translatable?(Article, "title")
    end

    test "is false for a field that is not declared translatable" do
      refute Translate.translatable?(Article, :id)
      refute Translate.translatable?(Article, "id")
    end

    test "raises for a module that does not use Localize.Translate" do
      assert_raise RuntimeError, ~r/must use `Localize.Translate`/, fn ->
        Translate.translatable?(URI, :title)
      end
    end
  end
end
