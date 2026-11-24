defmodule Localize.Translate.DefaultLocaleTest.Sites do
  @moduledoc false

  # Stands in for an application that keeps each site's language at runtime.
  def default_locale(%{site_locale: locale}, _fallback) do
    locale
  end

  def default_locale(nil, fallback) do
    fallback
  end
end

defmodule Localize.Translate.DefaultLocaleTest.Page do
  @moduledoc false

  # A struct whose base fields are in the language of the site it belongs to.
  use Localize.Translate,
    translates: [:title],
    default_locale: {Localize.Translate.DefaultLocaleTest.Sites, :default_locale, [nil]}

  defstruct title: nil, site_locale: nil, translations: %{}
end

defmodule Localize.Translate.DefaultLocaleTest.FrenchComment do
  @moduledoc false

  # The comments table, read as a site whose default language is French.
  use Ecto.Schema

  use Localize.Translate,
    translates: [:comment],
    container: :transcriptions,
    default_locale: {Localize.Translate.DefaultLocaleTest.Sites, :default_locale, [:fr]}

  schema "comments" do
    field(:comment, :string)
    field(:transcriptions, :map)
  end
end

defmodule Localize.Translate.DefaultLocaleTest.UnknownDefaultComment do
  @moduledoc false

  # The comments table with a default locale function that knows no default for a query.
  use Ecto.Schema

  use Localize.Translate,
    translates: [:comment],
    container: :transcriptions,
    default_locale: {Localize.Translate.DefaultLocaleTest.Sites, :default_locale, [nil]}

  schema "comments" do
    field(:comment, :string)
    field(:transcriptions, :map)
  end
end

defmodule Localize.Translate.DefaultLocaleTest do
  use Localize.Translate.TestCase

  import Localize.Translate.QueryBuilder

  alias Localize.Translate
  alias Localize.Translate.{Book, Comment}

  alias Localize.Translate.DefaultLocaleTest.{
    FrenchComment,
    Page,
    UnknownDefaultComment
  }

  defp french_page do
    %Page{
      title: "Bonjour",
      site_locale: :fr,
      translations: %{"en" => %{"title" => "Hello"}, "es" => %{"title" => "Hola"}}
    }
  end

  defp insert_french_comment do
    Repo.insert!(%Comment{
      comment: "Bonjour",
      transcriptions: %{"en" => %{"comment" => "Hello"}, "es" => %{"comment" => "Hola"}}
    })
  end

  defp select_one(query, id) do
    query
    |> where([c], c.id == ^id)
    |> Repo.one()
  end

  describe "default_locale/1" do
    test "returns a locale given as an atom or a string as a CLDR locale id" do
      assert Translate.default_locale(Comment) == :en
      assert Translate.default_locale(%Comment{}) == :en
    end

    test "calls a function default with the struct" do
      assert Translate.default_locale(french_page()) == :fr
      assert Translate.default_locale(%Page{site_locale: "es-MX"}) == :"es-MX"
    end

    test "calls a function default with nil for a module" do
      assert Translate.default_locale(FrenchComment) == :fr
      assert is_nil(Translate.default_locale(Page))
    end

    test "is nil when the function returns nil or a value that is not a locale" do
      for value <- [nil, "not a locale", "", 42, %{}] do
        assert is_nil(Translate.default_locale(%Page{site_locale: value})), inspect(value)
      end
    end

    test "translations/1 generates an embed for every locale with a function default" do
      module =
        quote do
          defmodule FunctionDefaultArticle do
            use Ecto.Schema

            use Localize.Translate,
              translates: [:title],
              locales: [:en, :fr],
              default_locale: {Localize.Translate.DefaultLocaleTest.Sites, :default_locale, [:en]}

            schema "articles" do
              field(:title, :string)
              translations(:translations)
            end
          end
        end

      {article, _bytecode} =
        module
        |> Code.compile_quoted()
        |> List.keyfind(FunctionDefaultArticle, 0)

      assert article.__trans__(:default_locale) ==
               {Localize.Translate.DefaultLocaleTest.Sites, :default_locale, [:en]}

      assert Module.concat(article, Translations).__schema__(:embeds) == [:en, :fr]
    end

    test "rejects an option that is neither a locale nor a function tuple" do
      module =
        quote do
          defmodule BadDefault do
            use Localize.Translate, translates: [:title], default_locale: [:en]
            defstruct title: nil, translations: %{}
          end
        end

      assert_raise ArgumentError, ~r/:default_locale must be a locale/, fn ->
        Code.eval_quoted(module)
      end
    end
  end

  describe "translate/2,3 with a function default" do
    test "reads the base field for the record's own default locale" do
      assert Translate.translate(french_page(), :title, :fr) == "Bonjour"
      assert Translate.translate!(french_page(), :title, :fr) == "Bonjour"
    end

    test "reads the container for any other locale" do
      assert Translate.translate(french_page(), :title, :en) == "Hello"
      assert Translate.translate(french_page(), :title, [:de, :es]) == "Hola"
    end

    test "ends a chain at the default locale" do
      assert Translate.translate(french_page(), :title, [:fr, :es]) == "Bonjour"
    end

    test "translates a whole struct" do
      assert Translate.translate(french_page(), :en).title == "Hello"
      assert Translate.translate(french_page(), :fr).title == "Bonjour"
    end

    test "treats every locale as a container lookup when no default resolves" do
      page = %{french_page() | site_locale: nil}

      assert Translate.translate(page, :title, :en) == "Hello"
      assert Translate.translate(page, :title, :fr) == "Bonjour"
    end
  end

  describe "translated/3 with a literal fallback chain" do
    test "moves past a locale with no translation" do
      book = insert(:book)
      id = book.id

      title =
        select_one(from(a in Book, select: translated(Book, a.title, [:it, :es])), id)

      assert title == book.translations.es.title
    end

    test "ends the chain at the default locale" do
      book = insert(:book)
      id = book.id

      title =
        select_one(from(a in Book, select: translated(Book, a.title, [:it, :en, :es])), id)

      assert title == book.title
    end

    test "returns the base column when no locale matches" do
      book = insert(:book)
      id = book.id

      title = select_one(from(a in Book, select: translated(Book, a.title, [:it, :de])), id)

      assert title == book.title
    end

    test "agrees with a runtime chain and with translate/3" do
      book = insert(:book)
      id = book.id

      for chain <- [[:it, :es], [:it, :en, :es], [:es], [:en], [:it], [:fr, :es]] do
        literal =
          case chain do
            [:it, :es] -> from(a in Book, select: translated(Book, a.title, [:it, :es]))
            [:it, :en, :es] -> from(a in Book, select: translated(Book, a.title, [:it, :en, :es]))
            [:es] -> from(a in Book, select: translated(Book, a.title, [:es]))
            [:en] -> from(a in Book, select: translated(Book, a.title, [:en]))
            [:it] -> from(a in Book, select: translated(Book, a.title, [:it]))
            [:fr, :es] -> from(a in Book, select: translated(Book, a.title, [:fr, :es]))
          end

        runtime = from(a in Book, select: translated(Book, a.title, chain))
        expected = Translate.translate(book, :title, chain)

        assert select_one(literal, id) == expected, inspect(chain)
        assert select_one(runtime, id) == expected, inspect(chain)
      end
    end
  end

  describe "translated/4 with a function default" do
    test "the schema's function is called with nil" do
      %{id: id} = insert_french_comment()
      locale = :en

      assert select_one(
               from(c in FrenchComment, select: translated(FrenchComment, c.comment, :fr)),
               id
             ) == "Bonjour"

      assert select_one(
               from(c in FrenchComment, select: translated(FrenchComment, c.comment, :en)),
               id
             ) == "Hello"

      assert select_one(
               from(c in FrenchComment, select: translated(FrenchComment, c.comment, locale)),
               id
             ) == "Hello"
    end

    test "the :default_locale option overrides the schema" do
      %{id: id} = insert_french_comment()
      default = "fr"
      locale = :fr

      assert select_one(
               from(c in Comment,
                 select: translated(Comment, c.comment, :fr, default_locale: default)
               ),
               id
             ) == "Bonjour"

      assert select_one(
               from(c in Comment,
                 select: translated(Comment, c.comment, [:de, :en], default_locale: default)
               ),
               id
             ) == "Hello"

      assert select_one(
               from(c in Comment,
                 select: translated(Comment, c.comment, locale, default_locale: default)
               ),
               id
             ) == "Bonjour"
    end

    test "with no default every locale is looked up in the container" do
      %{id: id} = insert_french_comment()
      locales = [:en]

      assert select_one(
               from(c in UnknownDefaultComment,
                 select: translated(UnknownDefaultComment, c.comment, :en)
               ),
               id
             ) == "Hello"

      assert select_one(
               from(c in UnknownDefaultComment,
                 select: translated(UnknownDefaultComment, c.comment, locales)
               ),
               id
             ) == "Hello"

      assert select_one(
               from(c in UnknownDefaultComment,
                 select: translated(UnknownDefaultComment, c.comment, :fr)
               ),
               id
             ) == "Bonjour"
    end

    test "an invalid :default_locale option is no default" do
      %{id: id} = insert_french_comment()

      for default <- [nil, "not a locale", "", 42] do
        assert select_one(
                 from(c in Comment,
                   select: translated(Comment, c.comment, :en, default_locale: default)
                 ),
                 id
               ) == "Hello",
               inspect(default)
      end
    end

    test "translated_as/4 takes the option" do
      %{id: id} = insert_french_comment()

      row =
        select_one(
          from(c in Comment,
            select: %{comment: translated_as(Comment, c.comment, :fr, default_locale: :fr)}
          ),
          id
        )

      assert row == %{comment: "Bonjour"}
    end

    test "options that are not a literal keyword list fail to compile" do
      query =
        quote do
          import Ecto.Query
          import Localize.Translate.QueryBuilder
          options = [default_locale: :fr]

          from(c in Localize.Translate.Comment,
            select: translated(Comment, c.comment, :fr, options)
          )
        end

      assert_raise ArgumentError, ~r/must be a literal keyword list/, fn ->
        Code.eval_quoted(query)
      end
    end
  end
end
