defmodule Localize.Translate.LongChainTest.AnyLocaleComment do
  @moduledoc false

  # The comments table with no locale list, so a chain is never shortened by it.
  use Ecto.Schema
  use Localize.Translate, translates: [:comment], container: :transcriptions, default_locale: :en

  schema "comments" do
    field(:comment, :string)
    field(:transcriptions, :map)
  end
end

defmodule Localize.Translate.LongChainTest do
  use Localize.Translate.TestCase

  import Localize.Translate.QueryBuilder

  alias Localize.Translate
  alias Localize.Translate.LongChainTest.AnyLocaleComment

  setup do
    comment =
      Repo.insert!(%AnyLocaleComment{
        comment: "English",
        transcriptions: %{"pt" => %{"comment" => "Português"}, "fr" => %{"comment" => "Français"}}
      })

    [comment: comment]
  end

  defp field_value(id, locales) do
    Repo.one(
      from(c in AnyLocaleComment,
        where: c.id == ^id,
        select: translated(AnyLocaleComment, c.comment, locales)
      )
    )
  end

  defp record_value(id, locales) do
    Repo.one(
      from(c in AnyLocaleComment,
        where: c.id == ^id,
        select: translated(AnyLocaleComment, c, locales)
      )
    )
  end

  describe "a chain longer than the unrolled steps" do
    test "finds a translation past the fourth locale, as translate/3 does", %{comment: comment} do
      locales = [:de, :it, :ja, :ko, :nl, :pt]

      assert field_value(comment.id, locales) == "Português"
      assert Translate.translate(comment, :comment, locales) == "Português"
      assert record_value(comment.id, locales) == %{"comment" => "Português"}
    end

    test "stops at the default locale past the fourth locale", %{comment: comment} do
      locales = [:de, :it, :ja, :ko, :en, :pt]

      assert field_value(comment.id, locales) == "English"
      assert Translate.translate(comment, :comment, locales) == "English"
    end

    test "falls back to the base column when nothing in a long chain matches", %{comment: comment} do
      locales = [:de, :it, :ja, :ko, :nl, :sv]

      assert field_value(comment.id, locales) == "English"
      assert is_nil(record_value(comment.id, locales))
    end

    test "agrees with translate/3 for chains of every length", %{comment: comment} do
      for length <- 0..7 do
        locales = Enum.take([:de, :it, :ja, :fr, :ko, :nl, :pt], length)

        assert field_value(comment.id, locales) == Translate.translate(comment, :comment, locales),
               inspect(locales)
      end
    end
  end

  describe "a LanguageTag locale" do
    test "reads its CLDR chain in the unrolled steps", %{comment: comment} do
      {:ok, tag} = Localize.LanguageTag.new("fr-CA")

      assert field_value(comment.id, tag) == "Français"
      assert record_value(comment.id, tag) == %{"comment" => "Français"}
      assert Translate.translate(comment, :comment, tag) == "Français"
    end
  end
end
