defmodule Localize.TranslateTest do
  use Localize.Translate.TestCase

  alias Localize.Translate
  alias Localize.Translate.{Article, Comment}

  doctest Translate

  test "checks whether a field is translatable or not given a module" do
    assert Translate.translatable?(Article, :title) == true
    assert Translate.translatable?(Article, "title") == true
    assert Translate.translatable?(Article, :fake_field) == false
  end

  test "checks whether a field is translatable or not given a struct" do
    with article <- build(:article) do
      assert Translate.translatable?(article, :title) == true
      assert Translate.translatable?(article, "title") == true
      assert Translate.translatable?(article, :fake_field) == false
    end
  end

  test "returns the default translation container when unspecified" do
    assert Article.__trans__(:container) == :translations
  end

  test "the default locale set per schema" do
    assert Article.__trans__(:default_locale) == :en
  end

  test "per-schema default locale" do
    defmodule Pamphlet do
      use Translate, translates: [:title, :body], default_locale: :fr
      defstruct title: "", body: "", translations: %{}
    end

    assert Pamphlet.__trans__(:default_locale) == :fr
  end

  test "returns the custom translation container name if specified" do
    assert Comment.__trans__(:container) == :transcriptions
  end

  test "compilation fails when translation container is not a valid field" do
    invalid_module =
      quote do
        defmodule TestArticle do
          use Localize.Translate, translates: [:title, :body], container: :invalid_container
          defstruct title: "", body: "", translations: %{}
        end
      end

    assert_raise ArgumentError,
                 "The field invalid_container used as the translation container is not defined in TestArticle struct",
                 fn -> Code.eval_quoted(invalid_module) end
  end

  test "translations/3 macro with explicit locales" do
    assert :translations in Translate.Magazine.__schema__(:fields)

    assert [:es, :it, :de] = Translate.Magazine.Translations.__schema__(:fields)

    assert [:title, :body] = Translate.Magazine.Translations.Fields.__schema__(:fields)

    assert {
             :parameterized,
             {Ecto.Embedded,
              %Ecto.Embedded{
                cardinality: :one,
                field: :translations,
                on_cast: nil,
                on_replace: :update,
                ordered: true,
                owner: Translate.Magazine,
                related: Translate.Magazine.Translations,
                unique: true
              }}
           } = Translate.Magazine.__schema__(:type, :translations)
  end

  test "translations/1 macro uses configured locales (default locale excluded)" do
    assert :translations in Translate.Brochure.__schema__(:fields)

    assert [:ar, :de, :doi, :"en-AU", :"fr-CA", :ja, :nb, :no, :pl, :th] =
             Translate.Brochure.Translations.__schema__(:fields)

    assert [:title, :body] = Translate.Brochure.Translations.Fields.__schema__(:fields)

    assert {
             :parameterized,
             {Ecto.Embedded,
              %Ecto.Embedded{
                cardinality: :one,
                field: :translations,
                on_cast: nil,
                on_replace: :update,
                ordered: true,
                owner: Translate.Brochure,
                related: Translate.Brochure.Translations,
                unique: true
              }}
           } = Translate.Brochure.__schema__(:type, :translations)
  end

  test "Confirm translations embedded schemas have no docs" do
    assert {:docs_v1, _, :elixir, "text/markdown", :hidden, %{}, _} =
             Code.fetch_docs(Translate.Brochure.Translations)

    assert {:docs_v1, _, :elixir, "text/markdown", :hidden, %{}, _} =
             Code.fetch_docs(Translate.Brochure.Translations.Fields)
  end
end
