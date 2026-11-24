defmodule Localize.Translate.FallbackTest do
  @moduledoc """
  Covers the fallback branches and error paths of `translate/2,3` and
  `translate!/3` — the cases where a translation is absent, explicitly `nil`,
  or the field is not translatable at all.

  """

  use Localize.Translate.TestCase, async: true

  alias Localize.Translate
  alias Localize.Translate.Comment

  describe "translate/3 when no translation exists" do
    test "falls back to the base value" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert Translate.translate(comment, :comment, :es) == "English comment"
    end

    test "falls back when the translation is explicitly nil" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => nil}}
      }

      assert Translate.translate(comment, :comment, :es) == "English comment"
    end

    test "falls back when the locale is absent from the container" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, :es) == "English comment"
    end
  end

  describe "translate/3 with a fallback chain" do
    test "takes the first locale in the chain that has a translation" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, [:es, :fr]) == "Commentaire"
    end

    test "a nil translation counts as missing and the chain moves on" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => nil}, "fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, [:es, :fr]) == "Commentaire"
    end

    test "a nil base value at the default locale counts as missing too" do
      comment = %Comment{
        comment: nil,
        transcriptions: %{"fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, [:en, :fr]) == "Commentaire"
    end

    test "falls back to the base value when no locale in the chain matches" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert Translate.translate(comment, :comment, [:es, :fr]) == "English comment"
    end
  end

  describe "translate/3 with a field that is not translatable" do
    test "returns the base value" do
      article = %{build(:article) | id: 42}

      assert Translate.translate(article, :id, :es) == 42
      assert Translate.translate(article, "id", :es) == 42
    end

    test "returns nil for a field the struct does not have" do
      article = build(:article)

      assert is_nil(Translate.translate(article, :no_such_field, :es))
      assert is_nil(Translate.translate(article, "no_such_field", :es))
      assert is_nil(Translate.translate(article, :__struct__, :es))
      assert is_nil(Translate.translate(article, 42, :es))
    end

    test "translates a field given as a string" do
      article = build(:article)

      assert Translate.translate(article, "title", :es) == article.translations.es.title
    end

    test "never creates an atom from a string field" do
      field = "definitely_not_an_existing_atom_#{System.unique_integer([:positive])}"

      assert is_nil(Translate.translate(build(:article), field, :es))

      assert_raise ArgumentError, fn ->
        String.to_existing_atom(field)
      end
    end

    test "returns the base value for a struct that does not use Localize.Translate" do
      assert Translate.translate(URI.parse("https://example.com"), :host, :es) == "example.com"
    end
  end

  describe "translate/1,2,3 with a value that is not a struct" do
    test "translate/1 and translate/2 return it unchanged" do
      for value <- [nil, "text", 42, %{"title" => "plain map"}, [1, 2]] do
        assert Translate.translate(value) == value
        assert Translate.translate(value, :es) == value
      end
    end

    test "translate/3 returns nil" do
      for value <- [nil, "text", 42, %{title: "plain map"}, [1, 2]] do
        assert is_nil(Translate.translate(value, :title, :es)), inspect(value)
      end
    end
  end

  describe "translate/2,3 with an invalid locale" do
    test "translate/3 falls back to the base value" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      for locale <- [:xyzabc, "not a locale", "", :"", nil, 42, %{}, [nil]] do
        assert Translate.translate(comment, :comment, locale) == "English comment",
               inspect(locale)
      end
    end

    test "translate/3 reads the base value for a language CLDR has no data for" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"und" => %{"comment" => "Root"}, "es" => %{"comment" => "Comentario"}}
      }

      assert Translate.translate(comment, :comment, "tlh") == "English comment"
      assert Translate.translate(comment, :comment, ["tlh", :es]) == "Comentario"
    end

    test "translate/3 skips an invalid locale in a chain" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      assert Translate.translate(comment, :comment, [:xyzabc, nil, "es"]) == "Comentario"
    end

    test "translate/2 leaves the struct untranslated" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      for locale <- ["not a locale", "", nil, 42] do
        assert Translate.translate(comment, locale).comment == "English comment",
               inspect(locale)
      end
    end
  end

  describe "translate!/3" do
    test "raises the locale error for an invalid locale" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      for locale <- ["not a locale", nil, [:es, nil]] do
        assert_raise Localize.InvalidLocaleError, fn ->
          Translate.translate!(comment, :comment, locale)
        end
      end
    end

    test "returns the translation when one exists" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      assert Translate.translate!(comment, :comment, :es) == "Comentario"
    end

    test "raises rather than falling back when no translation exists" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert_raise RuntimeError, ~r/translation doesn't exist/, fn ->
        Translate.translate!(comment, :comment, :es)
      end
    end

    test "raises when the only translation is nil" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => nil}}
      }

      assert_raise RuntimeError, ~r/translation doesn't exist/, fn ->
        Translate.translate!(comment, :comment, :es)
      end
    end

    test "raises naming every locale in the chain" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert_raise RuntimeError, ~r/in locales/, fn ->
        Translate.translate!(comment, :comment, [:es, :fr])
      end
    end

    test "raises an ArgumentError for a field that is not translatable" do
      article = build(:article)

      for field <- [:id, "id", :no_such_field, 42] do
        assert_raise ArgumentError, ~r/does not declare .* as translatable/, fn ->
          Translate.translate!(article, field, :es)
        end
      end
    end

    test "raises an ArgumentError for a value that is not a translatable struct" do
      for value <- [nil, %{title: "plain map"}, URI.parse("https://example.com")] do
        assert_raise ArgumentError, fn ->
          Translate.translate!(value, :title, :es)
        end
      end
    end

    test "accepts the field as a string" do
      article = build(:article)

      assert Translate.translate!(article, "title", :es) == article.translations.es.title
    end
  end

  describe "translate/2 over a whole struct" do
    test "leaves a field untouched when it has no translation" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => "Comentario"}}
      }

      assert Translate.translate(comment, :es).comment == "Comentario"
    end

    test "leaves every field untouched when the locale has no translations" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert Translate.translate(comment, :es).comment == "English comment"
    end

    test "leaves an unloaded association untouched" do
      article =
        :article
        |> build()
        |> Map.put(:comments, %Ecto.Association.NotLoaded{})

      translated = Translate.translate(article, :es)

      assert %Ecto.Association.NotLoaded{} = translated.comments
    end
  end

  describe "when the base value is also nil" do
    test "translate/3 returns nil rather than raising" do
      comment = %Comment{comment: nil, transcriptions: %{"es" => %{"comment" => nil}}}

      assert Translate.translate(comment, :comment, :es) == nil
    end

    test "a nil result does not halt a fallback chain early" do
      comment = %Comment{
        comment: nil,
        transcriptions: %{"es" => %{"comment" => nil}, "fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, [:es, :fr]) == "Commentaire"
    end

    test "translate/2 leaves a nil field as nil" do
      comment = %Comment{comment: nil, transcriptions: %{"es" => %{"comment" => nil}}}

      assert Translate.translate(comment, :es).comment == nil
    end
  end

  describe "translate/2 with an association that is neither a struct nor a list" do
    test "leaves a nil association untouched" do
      article =
        :article
        |> build()
        |> Map.put(:comments, nil)

      assert Translate.translate(article, :es).comments == nil
    end
  end

  describe "compile-time validation" do
    test "rejects a schema declaring a translatable field the schema does not define" do
      source = """
      defmodule Localize.Translate.InvalidFieldFixture do
        use Ecto.Schema

        use Localize.Translate,
          translates: [:title, :nonexistent],
          locales: [:en, :es],
          default_locale: :en

        schema "articles" do
          field(:title, :string)
          embeds_one :translations, Translations, on_replace: :update, primary_key: false do
            embeds_one(:es, __MODULE__.Fields, on_replace: :update)
          end
        end
      end
      """

      assert_raise ArgumentError, ~r/declares .* as translatable/, fn ->
        Code.compile_string(source)
      end
    end

    test "names every undefined field when more than one is declared" do
      source = """
      defmodule Localize.Translate.InvalidFieldsFixture do
        use Ecto.Schema

        use Localize.Translate,
          translates: [:title, :missing_one, :missing_two],
          locales: [:en, :es],
          default_locale: :en

        schema "articles" do
          field(:title, :string)
          embeds_one :translations, Translations, on_replace: :update, primary_key: false do
            embeds_one(:es, __MODULE__.Fields, on_replace: :update)
          end
        end
      end
      """

      assert_raise ArgumentError, ~r/they are not defined/, fn ->
        Code.compile_string(source)
      end
    end
  end
end
