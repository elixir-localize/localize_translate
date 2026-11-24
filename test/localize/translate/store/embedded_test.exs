defmodule Localize.Translate.Store.EmbeddedTest do
  use Localize.Translate.TestCase, async: true

  alias Localize.Translate.Article
  alias Localize.Translate.Store.Embedded

  describe "queryable?/0" do
    test "reports that predicates can be pushed into the data layer" do
      assert Embedded.queryable?() == true
    end
  end

  describe "fetch_translation/4 with a struct container" do
    test "returns the translation for a locale that has one" do
      article = build(:article)

      assert {:ok, title} = Embedded.fetch_translation(article, :es, :title, [])
      assert title == article.translations.es.title
    end

    test "accepts the locale as a string" do
      article = build(:article)

      assert Embedded.fetch_translation(article, "es", :title, []) ==
               Embedded.fetch_translation(article, :es, :title, [])
    end

    test "returns :error for a locale with no translations" do
      article = build(:article)

      assert Embedded.fetch_translation(article, :it, :title, []) == :error
    end

    test "returns :error for an unknown locale that has no atom" do
      article = build(:article)

      assert Embedded.fetch_translation(article, "definitely-not-a-locale", :title, []) == :error
    end

    test "returns :error when the container itself is nil" do
      article = %Article{title: "Title", translations: nil}

      assert Embedded.fetch_translation(article, :es, :title, []) == :error
    end
  end

  describe "fetch_translation/4 with a map container" do
    test "reads string-keyed locales and fields, as a jsonb column loads them" do
      article = %Article{
        title: "Title",
        translations: %{"es" => %{"title" => "Título", "body" => "Cuerpo"}}
      }

      assert Embedded.fetch_translation(article, :es, :title, []) == {:ok, "Título"}
      assert Embedded.fetch_translation(article, "es", :body, []) == {:ok, "Cuerpo"}
    end

    test "returns :error for a field the locale does not carry" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      assert Embedded.fetch_translation(article, :es, :body, []) == :error
    end

    test "returns :error for a locale the container does not carry" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      assert Embedded.fetch_translation(article, :fr, :title, []) == :error
    end
  end

  describe "put_translation/5" do
    test "adds a translation to a locale that already has one" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      assert {:ok, updated} = Embedded.put_translation(article, :es, :body, "Cuerpo", [])
      assert Embedded.fetch_translation(updated, :es, :body, []) == {:ok, "Cuerpo"}
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Título"}
    end

    test "adds a locale that the container does not yet carry" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      assert {:ok, updated} = Embedded.put_translation(article, :fr, :title, "Titre", [])
      assert Embedded.fetch_translation(updated, :fr, :title, []) == {:ok, "Titre"}
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Título"}
    end

    test "creates the container when it is nil" do
      article = %Article{translations: nil}

      assert {:ok, updated} = Embedded.put_translation(article, :es, :title, "Título", [])
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Título"}
    end

    test "overwrites an existing value" do
      article = %Article{translations: %{"es" => %{"title" => "Antiguo"}}}

      assert {:ok, updated} = Embedded.put_translation(article, :es, :title, "Nuevo", [])
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Nuevo"}
    end

    test "a written translation is readable through translate/3" do
      article = %Article{title: "English title", translations: %{}}
      {:ok, updated} = Embedded.put_translation(article, :es, :title, "Título", [])

      assert Localize.Translate.translate(updated, :title, :es) == "Título"
    end
  end

  describe "locales/2" do
    test "lists the locales of a struct container" do
      article = build(:article)

      assert Enum.sort(Embedded.locales(article, [])) == [:es, :fr]
    end

    test "lists the locales of a map container as atoms" do
      article = %Article{translations: %{"es" => %{}, "fr" => %{}}}

      assert Enum.sort(Embedded.locales(article, [])) == [:es, :fr]
    end

    test "returns an empty list when the container is nil" do
      assert Embedded.locales(%Article{translations: nil}, []) == []
    end

    test "returns an empty list when the container is empty" do
      assert Embedded.locales(%Article{translations: %{}}, []) == []
    end
  end

  describe "malformed containers" do
    test "fetch_translation/4 is a miss for a container or entry that is not a map" do
      for translations <- [
            "garbage",
            42,
            [1],
            %{"es" => "a string"},
            %{"es" => [1]},
            %{"es" => 42}
          ] do
        article = %Article{title: "Title", translations: translations}

        assert Embedded.fetch_translation(article, :es, :title, []) == :error,
               inspect(translations)
      end
    end

    test "fetch_translation/4 is a miss for a locale or field that is not a name" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      for {locale, field} <- [{42, :title}, {:es, 42}, {:es, nil}, {%{}, :title}] do
        assert Embedded.fetch_translation(article, locale, field, []) == :error,
               inspect({locale, field})
      end
    end

    test "translate/3 falls back to the base value instead of raising" do
      for translations <- ["garbage", %{"es" => "a string"}, %{"es" => %{"title" => nil}}] do
        article = %Article{title: "Title", translations: translations}

        assert Localize.Translate.translate(article, :title, :es) == "Title",
               inspect(translations)
      end
    end

    test "locales/2 is empty for a container that is not a map" do
      for translations <- ["garbage", 42, [1]] do
        assert Embedded.locales(%Article{translations: translations}, []) == [],
               inspect(translations)
      end
    end

    test "locales/2 leaves out keys that are not known locale names" do
      article = %Article{translations: %{"es" => %{}, "definitely-not-an-atom-zz9" => %{}}}

      assert Embedded.locales(article, []) == [:es]
    end

    test "put_translation/5 returns an error for a container that is not a map" do
      article = %Article{translations: "garbage"}

      assert {:error, %ArgumentError{}} = Embedded.put_translation(article, :es, :title, "T")
    end

    test "put_translation/5 returns an error for a locale entry that is not a map" do
      article = %Article{translations: %{"es" => "a string"}}

      assert {:error, %ArgumentError{}} = Embedded.put_translation(article, :es, :title, "T")
    end

    test "put_translation/5 refuses a locale or field a struct container does not define" do
      article = build(:article)

      for {locale, field} <- [
            {:it, :title},
            {"zz-not-a-locale", :title},
            {:es, :nope},
            {:es, "__struct__"},
            {"__struct__", :title}
          ] do
        assert {:error, %ArgumentError{}} = Embedded.put_translation(article, locale, field, "T"),
               inspect({locale, field})
      end

      assert is_struct(article.translations, Article.Translations)
    end

    test "put_translation/5 refuses a nil or empty locale or field on a map container" do
      article = %Article{translations: %{}}

      for {locale, field} <- [{nil, :title}, {"", :title}, {:es, nil}, {:es, ""}, {42, :title}] do
        assert {:error, %ArgumentError{}} = Embedded.put_translation(article, locale, field, "T"),
               inspect({locale, field})
      end
    end

    test "put_translation/5 fills a locale whose entry is nil" do
      article = %Article{translations: %{"es" => nil}}

      assert {:ok, updated} = Embedded.put_translation(article, :es, :title, "Título")
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Título"}
    end
  end

  describe "store selection" do
    test "a schema defaults to the embedded store" do
      assert Article.__trans__(:store) == Embedded
    end
  end

  describe "default arguments and key styles" do
    test "options may be omitted on fetch_translation/3" do
      article = build(:article)

      assert {:ok, _title} = Embedded.fetch_translation(article, :es, :title)
    end

    test "options may be omitted on locales/1" do
      article = build(:article)

      assert Enum.sort(Embedded.locales(article)) == [:es, :fr]
    end

    test "options may be omitted on put_translation/4" do
      article = %Article{translations: %{}}

      assert {:ok, _updated} = Embedded.put_translation(article, :es, :title, "Título")
    end

    test "a nil locale is a miss" do
      article = build(:article)

      assert Embedded.fetch_translation(article, nil, :title, []) == :error
    end

    test "a nil locale is a miss against a map container too" do
      article = %Article{translations: %{"es" => %{"title" => "Título"}}}

      assert Embedded.fetch_translation(article, nil, :title, []) == :error
    end

    test "reads a struct container with a string field name" do
      article = build(:article)

      assert Embedded.fetch_translation(article, :es, "title", []) ==
               Embedded.fetch_translation(article, :es, :title, [])
    end

    test "writes into a struct container keeping atom keys" do
      article = build(:article)

      assert {:ok, updated} = Embedded.put_translation(article, :es, :title, "Nuevo", [])
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Nuevo"}
      assert is_struct(updated.translations)
    end

    test "writes into a struct container given string locale and field" do
      article = build(:article)

      assert {:ok, updated} = Embedded.put_translation(article, "es", "title", "Nuevo", [])
      assert Embedded.fetch_translation(updated, :es, :title, []) == {:ok, "Nuevo"}
    end
  end
end
