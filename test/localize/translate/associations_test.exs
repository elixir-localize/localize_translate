defmodule Localize.Translate.AssociationsTest.Note do
  @moduledoc false

  # A plain struct, not an Ecto schema, using `Localize.Translate`.
  use Localize.Translate, translates: [:text], container: :translations, default_locale: :en

  defstruct text: nil, translations: %{}, author: nil
end

defmodule Localize.Translate.AssociationsTest.Unloaded do
  @moduledoc false

  # Stands in for another data layer's marker for a relationship that was not loaded.
  defstruct field: nil
end

defmodule Localize.Translate.AssociationsTest.Resource do
  @moduledoc false

  # A module that defines `__trans__/1` itself, as a data layer other than Ecto does,
  # and names its own related-record fields.
  defstruct name: nil,
            translations: %{},
            notes: [],
            primary_note: nil,
            owner: nil,
            metadata: nil,
            missing_marker: nil

  def __trans__(:fields) do
    [:name]
  end

  def __trans__(:container) do
    :translations
  end

  def __trans__(:locales) do
    nil
  end

  def __trans__(:default_locale) do
    :en
  end

  def __trans__(:store) do
    Localize.Translate.Store.Embedded
  end

  def __trans__(:store_options) do
    []
  end

  def __trans__(:associations) do
    [:notes, :primary_note, :owner, :metadata, :missing_marker, :not_a_struct_field]
  end
end

defmodule Localize.Translate.AssociationsTest do
  use Localize.Translate.TestCase, async: true

  alias Localize.Translate
  alias Localize.Translate.{Article, Comment}
  alias Localize.Translate.AssociationsTest.{Note, Resource, Unloaded}

  defp note(text, french) do
    %Note{text: text, translations: %{"fr" => %{"text" => french}}}
  end

  describe "__trans__(:associations)" do
    test "is an Ecto schema's associations and embeds" do
      associations = Article.__trans__(:associations)

      assert :comments in associations
      assert :translations in associations
    end

    test "is empty for a plain struct" do
      assert Note.__trans__(:associations) == []
    end
  end

  describe "translate/2 over related records" do
    test "translates a loaded Ecto association" do
      article =
        build(:article)
        |> Map.put(:comments, [
          %Comment{comment: "Hello", transcriptions: %{"fr" => %{"comment" => "Bonjour"}}}
        ])

      [comment] = Translate.translate(article, :fr).comments

      assert comment.comment == "Bonjour"
    end

    test "translates a plain struct, which has no Ecto schema" do
      assert Translate.translate(note("Hello", "Bonjour"), :fr).text == "Bonjour"
    end

    test "translates the related records a module names itself" do
      resource = %Resource{
        name: "Photo",
        translations: %{"fr" => %{"name" => "Photographie"}},
        notes: [note("One", "Un"), %Unloaded{field: :x}, %{"text" => "plain"}, nil],
        primary_note: note("Main", "Principal"),
        owner: %Unloaded{field: :owner},
        metadata: %{"text" => "a plain map"},
        missing_marker: nil
      }

      translated = Translate.translate(resource, :"fr-CA")

      assert translated.name == "Photographie"
      assert translated.primary_note.text == "Principal"

      assert [%Note{text: "Un"}, %Unloaded{field: :x}, %{"text" => "plain"}, nil] =
               translated.notes

      assert translated.owner == %Unloaded{field: :owner}
      assert translated.metadata == %{"text" => "a plain map"}
      assert is_nil(translated.missing_marker)
      refute Map.has_key?(translated, :not_a_struct_field)
    end

    test "translates related records recursively" do
      inner = %Resource{name: "Inner", translations: %{"fr" => %{"name" => "Intérieur"}}}
      outer = %Resource{name: "Outer", notes: [], owner: inner}

      assert Translate.translate(outer, :fr).owner.name == "Intérieur"
    end
  end
end
