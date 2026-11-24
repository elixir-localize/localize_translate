defmodule Localize.Translate.ReflectionTest.Note do
  @moduledoc false
  require Localize.Translate

  defstruct text: nil, translations: %{}

  Localize.Translate.reflection(fields: [:text], default_locale: :en)
end

defmodule Localize.Translate.ReflectionTest.Page do
  @moduledoc false
  require Localize.Translate

  defstruct title: nil, texts: %{}, notes: [], owner: nil

  Localize.Translate.reflection(
    fields: [:title],
    container: :texts,
    locales: [:en, :fr],
    default_locale: {__MODULE__, :site_default, []},
    store: Localize.Translate.Store.Embedded,
    store_options: [],
    associations: [:notes, :owner]
  )

  def site_default(_subject) do
    :fr
  end
end

defmodule Localize.Translate.ReflectionTest do
  use ExUnit.Case, async: true

  alias Localize.Translate
  alias Localize.Translate.ReflectionTest.{Note, Page}

  describe "reflection/1 with defaults" do
    test "answers every key with its default" do
      assert Note.__trans__(:fields) == [:text]
      assert Note.__trans__(:container) == :translations
      assert is_nil(Note.__trans__(:locales))
      assert Note.__trans__(:default_locale) == :en
      assert Note.__trans__(:store) == Localize.Translate.Store.Embedded
      assert Note.__trans__(:store_options) == []
      assert Note.__trans__(:associations) == []
    end

    test "makes the module translatable" do
      note = %Note{text: "Hello", translations: %{"fr" => %{"text" => "Bonjour"}}}

      assert Translate.translatable?(Note, :text)
      assert Translate.translate(note, :text, :fr) == "Bonjour"
      assert Translate.translate(note, :text, :en) == "Hello"
    end
  end

  describe "reflection/1 with every option" do
    test "answers the values given" do
      assert Page.__trans__(:container) == :texts
      assert Page.__trans__(:locales) == [:en, :fr]
      assert Page.__trans__(:default_locale) == {Page, :site_default, []}
      assert Page.__trans__(:associations) == [:notes, :owner]
    end

    test "translates the related records it names, with a function default" do
      page = %Page{
        title: "Bonjour",
        texts: %{"en" => %{"title" => "Hello"}},
        notes: [%Note{text: "Note", translations: %{"en" => %{"text" => "A note"}}}]
      }

      assert Translate.default_locale(page) == :fr
      assert Translate.translate(page, :title, :fr) == "Bonjour"

      translated = Translate.translate(page, :en)
      assert translated.title == "Hello"
      assert [%Note{text: "Note"}] = translated.notes
    end
  end

  describe "reflection/1 with invalid options" do
    defp compile(options) do
      quote do
        defmodule unquote(Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")) do
          require Localize.Translate
          defstruct text: nil, translations: %{}
          Localize.Translate.reflection(unquote(options))
        end
      end
      |> Code.compile_quoted()
    end

    test "raises at compile time" do
      for options <- [
            [],
            [fields: :text],
            [fields: ["text"]],
            [fields: [:text], container: "translations"],
            [fields: [:text], locales: :en],
            [fields: [:text], default_locale: 42],
            [fields: [:text], store_options: :none],
            [fields: [:text], associations: :all]
          ] do
        assert_raise ArgumentError, ~r/reflection\/1/, fn -> compile(options) end
      end
    end
  end
end
