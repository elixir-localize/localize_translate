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

    test "a nil translation resolves to the base value and ends the chain" do
      comment = %Comment{
        comment: "English comment",
        transcriptions: %{"es" => %{"comment" => nil}, "fr" => %{"comment" => "Commentaire"}}
      }

      assert Translate.translate(comment, :comment, [:es, :fr]) == "English comment"
    end

    test "falls back to the base value when no locale in the chain matches" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert Translate.translate(comment, :comment, [:es, :fr]) == "English comment"
    end
  end

  describe "translate/3 with a non-translatable field" do
    test "raises naming the module and the field" do
      article = build(:article)

      assert_raise RuntimeError, ~r/must declare .* as translatable/, fn ->
        Translate.translate(article, :id, :es)
      end
    end
  end

  describe "translate!/3" do
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

    test "raises naming every locale in the chain" do
      comment = %Comment{comment: "English comment", transcriptions: %{}}

      assert_raise RuntimeError, ~r/in locales/, fn ->
        Translate.translate!(comment, :comment, [:es, :fr])
      end
    end

    test "raises for a non-translatable field" do
      article = build(:article)

      assert_raise RuntimeError, ~r/must declare .* as translatable/, fn ->
        Translate.translate!(article, :id, :es)
      end
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
      article = build(:article) |> Map.put(:comments, %Ecto.Association.NotLoaded{})

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
      article = build(:article) |> Map.put(:comments, nil)

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
