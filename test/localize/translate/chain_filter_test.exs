defmodule Localize.Translate.ChainFilterTest.Note do
  @moduledoc false
  require Localize.Translate

  # The default locale is not among the locales translations are stored for.
  defstruct name: nil, translations: %{}, tags: []

  Localize.Translate.reflection(
    fields: [:name],
    locales: [:es, :fr],
    default_locale: :en,
    associations: [:tags]
  )
end

defmodule Localize.Translate.ChainFilterTest.Tag do
  @moduledoc false
  require Localize.Translate

  # Holds translations for any locale, including ones its parent does not list.
  defstruct name: nil, translations: %{}

  Localize.Translate.reflection(fields: [:name], default_locale: :en)
end

defmodule Localize.Translate.ChainFilterTest.SpanishComment do
  @moduledoc false

  # The comments table, read as a schema whose default locale is not listed.
  use Ecto.Schema

  use Localize.Translate,
    translates: [:comment],
    container: :transcriptions,
    locales: [:es, :fr],
    default_locale: :en

  schema "comments" do
    field(:comment, :string)
    field(:transcriptions, :map)
  end
end

defmodule Localize.Translate.ChainFilterTest do
  use Localize.Translate.TestCase

  import Localize.Translate.QueryBuilder

  alias Localize.Translate
  alias Localize.Translate.ChainFilterTest.{Note, SpanishComment, Tag}
  alias Localize.Translate.QueryBuilder

  defp note do
    %Note{
      name: "Photo",
      translations: %{"es" => %{"name" => "Foto"}, "de" => %{"name" => "Bild"}},
      tags: [%Tag{name: "Landscape", translations: %{"de" => %{"name" => "Landschaft"}}}]
    }
  end

  describe "locale_chain/2 with :default_locale" do
    test "keeps the default locale when :supported filters the chain" do
      assert Translate.locale_chain([:en, :es], supported: [:es, :fr], default_locale: :en) == [
               :en,
               :es
             ]

      assert Translate.locale_chain([:en, :es], supported: [:es, :fr]) == [:es]
    end

    test "ignores a default that is not a valid locale, and changes nothing without :supported" do
      assert Translate.locale_chain([:en, :es], supported: [:es], default_locale: "not a locale") ==
               [:es]

      assert Translate.locale_chain([:en, :es], default_locale: :en) == [:en, :es]
    end
  end

  describe "translate/2,3 filter by :locales and keep the default locale" do
    test "reads the base field for an unlisted default locale" do
      assert Translate.translate(note(), :name, [:en, :es]) == "Photo"
      assert Translate.translate(note(), :name, :en) == "Photo"
      assert Translate.translate(note(), [:en, :es]).name == "Photo"
    end

    test "ignores a stored locale the schema does not list" do
      assert Translate.translate(note(), :name, :de) == "Photo"
      assert Translate.translate(note(), :name, [:de, :es]) == "Foto"

      assert_raise RuntimeError, ~r/translation doesn't exist/, fn ->
        Translate.translate!(note(), :name, :de)
      end
    end

    test "filters each related record by its own locales" do
      [tag] = Translate.translate(note(), :de).tags

      assert tag.name == "Landschaft"
    end
  end

  describe "QueryBuilder.translated/4 agrees with translate/3" do
    test "for an unlisted default locale and an unlisted stored locale" do
      comment =
        Repo.insert!(%SpanishComment{
          comment: "English",
          transcriptions: %{"es" => %{"comment" => "Español"}, "de" => %{"comment" => "Deutsch"}}
        })

      id = comment.id

      for locales <- [[:en, :es], [:en], [:de], [:de, :es], [:es]] do
        runtime =
          Repo.one(
            from(c in SpanishComment,
              where: c.id == ^id,
              select: translated(SpanishComment, c.comment, locales)
            )
          )

        assert runtime == Translate.translate(comment, :comment, locales), inspect(locales)
      end

      literal =
        Repo.one(
          from(c in SpanishComment,
            where: c.id == ^id,
            select: translated(SpanishComment, c.comment, [:en, :es])
          )
        )

      assert literal == "English"
    end

    test "list_to_sql_array/3 keeps the default locale" do
      assert QueryBuilder.list_to_sql_array([:en, :es], [:es, :fr], "en") == ["en", "es"]
      assert QueryBuilder.list_to_sql_array([:en, :es], [:es, :fr], nil) == ["es"]
      assert QueryBuilder.list_to_sql_array([:en, :es], [:es, :fr]) == ["es"]
    end
  end
end
