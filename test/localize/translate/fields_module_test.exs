defmodule Localize.Translate.FieldsModuleTest do
  @moduledoc """
  Covers the `:fields_module` option of `translations/3`, which embeds a
  caller's own per-locale schema in the generated `Translations` schema, the
  checks made on it when the parent compiles, and the hand-written path of
  `build_field_schema: false`.

  """

  use Localize.Translate.TestCase, async: true

  import Localize.Translate.QueryBuilder

  alias Localize.Translate
  alias Localize.Translate.Flyer
  alias Localize.Translate.FlyerTranslationFields
  alias Localize.Translate.Poster
  alias Localize.Translate.Store.Embedded

  @translated_at ~U[2026-11-23 10:00:00Z]

  defp flyer do
    %Flyer{
      title: "English title",
      body: "English body",
      translations: %Flyer.Translations{
        es: %FlyerTranslationFields{
          title: "Título",
          body: "Cuerpo",
          translated_by: "Ana",
          machine_translated: true,
          translated_at: @translated_at
        }
      }
    }
  end

  defp compile_schema(translations_call, fields_module_source \\ "") do
    name = "Localize.Translate.Scratch#{System.unique_integer([:positive])}"

    Code.compile_string("""
    #{String.replace(fields_module_source, "SCRATCH", name)}

    defmodule #{name} do
      use Ecto.Schema

      use Localize.Translate,
        translates: [:title, :body],
        locales: [:en, :es, :fr],
        default_locale: :en

      schema "articles" do
        field(:title, :string)
        field(:body, :string)
        #{String.replace(translations_call, "SCRATCH", name)}
      end
    end
    """)
  end

  describe "generated schemas" do
    test "the Translations schema is generated" do
      assert Code.ensure_loaded?(Flyer.Translations)
      assert :translations in Flyer.__schema__(:embeds)
    end

    test "no Fields schema is generated" do
      refute Code.ensure_loaded?(Flyer.Translations.Fields)
    end

    test "each non-default locale embeds the caller's schema" do
      assert Flyer.Translations.__schema__(:embeds) == [:es, :fr]

      for locale <- [:es, :fr] do
        embed = Flyer.Translations.__schema__(:embed, locale)

        assert embed.related == FlyerTranslationFields
        assert embed.cardinality == :one
        assert embed.on_replace == :update
      end
    end

    test "reflection is the same as for a generated Fields schema" do
      assert Flyer.__trans__(:fields) == [:title, :body]
      assert Flyer.__trans__(:container) == :translations
      assert Flyer.__trans__(:locales) == [:en, :es, :fr]
      assert Flyer.__trans__(:default_locale) == :en
    end
  end

  describe "translating" do
    test "a single field" do
      assert Translate.translate(flyer(), :title, :es) == "Título"
      assert Translate.translate(flyer(), :body, :es) == "Cuerpo"
    end

    test "the whole struct takes the translatable fields and nothing else" do
      translated = Translate.translate(flyer(), :es)

      assert translated.title == "Título"
      assert translated.body == "Cuerpo"
      assert Map.keys(translated) == Map.keys(flyer())
    end

    test "a locale with no translation falls back to the base value" do
      assert Translate.translate(flyer(), :title, :fr) == "English title"
      assert Translate.translate(flyer(), :title, :en) == "English title"
    end

    test "a field that is not translatable is refused, though the fields schema has it" do
      assert_raise RuntimeError, ~r/must declare ':translated_by' as translatable/, fn ->
        Translate.translate(flyer(), :translated_by, :es)
      end
    end

    test "a locale that holds only state has no translation to give" do
      flyer = %Flyer{
        title: "English title",
        body: "English body",
        translations: %Flyer.Translations{es: %FlyerTranslationFields{translated_by: "Ana"}}
      }

      assert Translate.translate(flyer, :title, :es) == "English title"
      assert Translate.translate(flyer, :es).body == "English body"
    end
  end

  describe "the embedded store" do
    test "fetches a translatable field" do
      assert Embedded.fetch_translation(flyer(), :es, :title) == {:ok, "Título"}
      assert Embedded.fetch_translation(flyer(), :fr, :title) == :error
    end

    test "puts a translation and keeps the locale's other fields" do
      assert {:ok, updated} = Embedded.put_translation(flyer(), :es, :title, "Nuevo")

      assert updated.translations.es.title == "Nuevo"
      assert updated.translations.es.body == "Cuerpo"
      assert updated.translations.es.translated_by == "Ana"
      assert updated.translations.es.translated_at == @translated_at
    end

    test "lists the locales" do
      assert Embedded.locales(flyer()) == [:es, :fr]
    end
  end

  describe "stored in the database" do
    setup do
      params = %{
        title: "English title",
        body: "English body",
        translations: %{
          es: %{
            title: "Título",
            body: "Cuerpo",
            translated_by: "Ana",
            machine_translated: true,
            translated_at: @translated_at
          },
          fr: %{title: "Titre"}
        }
      }

      flyer =
        %Flyer{}
        |> Flyer.changeset(params)
        |> Repo.insert!()

      [flyer: Repo.get!(Flyer, flyer.id)]
    end

    test "the per-locale state comes back with the translations", %{flyer: flyer} do
      assert %FlyerTranslationFields{} = flyer.translations.es
      assert flyer.translations.es.title == "Título"
      assert flyer.translations.es.translated_by == "Ana"
      assert flyer.translations.es.machine_translated == true
      assert flyer.translations.es.translated_at == @translated_at

      assert flyer.translations.fr.title == "Titre"
      assert flyer.translations.fr.machine_translated == false
      assert is_nil(flyer.translations.fr.translated_by)
    end

    test "the caller's changeset is used for each locale" do
      changeset = Flyer.changeset(%Flyer{}, %{translations: %{es: %{body: "Cuerpo"}}})

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset.changes.translations.changes.es)
    end

    test "a loaded record translates", %{flyer: flyer} do
      assert Translate.translate(flyer, :title, :es) == "Título"
      assert Translate.translate(flyer, :title, :fr) == "Titre"
      assert Translate.translate(flyer, :body, :fr) == "English body"
    end

    test "the query builder reads a translatable field", %{flyer: flyer} do
      query = from(f in Flyer, where: translated(Flyer, f.title, :es) == "Título", select: f.id)
      assert Repo.all(query) == [flyer.id]

      query = from(f in Flyer, where: translated(Flyer, f.title, :es) == "Ana", select: f.id)
      assert Repo.all(query) == []
    end

    test "the query builder falls back to the base column", %{flyer: flyer} do
      query =
        from(f in Flyer, where: f.id == ^flyer.id, select: translated(Flyer, f.body, :fr))

      assert Repo.one(query) == "English body"
    end

    test "a locale that holds only state is not NULL when queried whole" do
      flyer =
        %Flyer{}
        |> Flyer.changeset(%{title: "Base", translations: %{}})
        |> Ecto.Changeset.put_embed(:translations, %Flyer.Translations{
          es: %FlyerTranslationFields{translated_by: "Ana"}
        })
        |> Repo.insert!()

      query =
        from(f in Flyer,
          where: f.id == ^flyer.id and not is_nil(translated(Flyer, f, :es)),
          select: f.id
        )

      assert Repo.all(query) == [flyer.id]
    end
  end

  describe "the fields module is checked when the parent compiles" do
    test "a schema with every translatable field as a string compiles" do
      modules =
        compile_schema(
          "translations(:translations, Translations, fields_module: SCRATCH.Fields)",
          """
          defmodule SCRATCH.Fields do
            use Ecto.Schema

            @primary_key false
            embedded_schema do
              field(:title, :string)
              field(:body, :string)
              field(:note, :string)
            end
          end
          """
        )

      assert [module] =
               for(
                 {module, _bytecode} <- modules,
                 function_exported?(module, :__trans__, 1),
                 do: module
               )

      assert module.__trans__(:fields) == [:title, :body]

      assert Module.concat(module, Translations).__schema__(:embed, :es).related ==
               Module.concat(module, Fields)
    end

    test "a missing translatable field" do
      assert_raise ArgumentError, ~r/must define the translatable fields \[:body\]/, fn ->
        compile_schema(
          "translations(:translations, Translations, fields_module: SCRATCH.Fields)",
          """
          defmodule SCRATCH.Fields do
            use Ecto.Schema

            @primary_key false
            embedded_schema do
              field(:title, :string)
            end
          end
          """
        )
      end
    end

    test "a translatable field that is not a string" do
      assert_raise ArgumentError, ~r/\[:body\] of .* as :string/, fn ->
        compile_schema(
          "translations(:translations, Translations, fields_module: SCRATCH.Fields)",
          """
          defmodule SCRATCH.Fields do
            use Ecto.Schema

            @primary_key false
            embedded_schema do
              field(:title, :string)
              field(:body, :integer)
            end
          end
          """
        )
      end
    end

    test "a module that is not an Ecto schema" do
      assert_raise ArgumentError, ~r/is not an Ecto schema/, fn ->
        compile_schema("translations(:translations, Translations, fields_module: Enum)")
      end
    end

    test "a module that does not exist" do
      assert_raise ArgumentError, ~r/is not a compiled module/, fn ->
        compile_schema(
          "translations(:translations, Translations, fields_module: Localize.Translate.NoSuchFields)"
        )
      end
    end

    test "a value that is not a module" do
      assert_raise ArgumentError, ~r/is not a compiled module/, fn ->
        compile_schema(~s|translations(:translations, Translations, fields_module: "Fields")|)
      end
    end
  end

  describe "the options of translations/3 are checked when the parent compiles" do
    test "an unknown option" do
      assert_raise ArgumentError, ~r/unknown options \[:fields_modul\]/, fn ->
        compile_schema("translations(:translations, Translations, fields_modul: Enum)")
      end
    end

    test ":fields_module with build_field_schema: false" do
      assert_raise ArgumentError, ~r/both :fields_module and build_field_schema: false/, fn ->
        compile_schema("""
        translations(:translations, Translations,
          fields_module: Localize.Translate.FlyerTranslationFields,
          build_field_schema: false
        )
        """)
      end
    end

    test "the known options" do
      assert Translate.known_trans_options() == [:build_field_schema, :fields_module]
      assert Translate.__validate_trans_options__(Flyer, []) == :ok
      assert Translate.__validate_trans_options__(Flyer, build_field_schema: true) == :ok
    end
  end

  describe "build_field_schema: false, with both schemas written by hand" do
    setup do
      poster = %Poster{
        title: "English title",
        body: "English body",
        translations: %Poster.Translations{
          es: %Poster.Translations.Fields{title: "Título", body: "Cuerpo", reviewed: true}
        }
      }

      [poster: poster]
    end

    test "the container embeds the hand-written schema" do
      assert Poster.__schema__(:embed, :translations).related == Poster.Translations
      assert Poster.Translations.__schema__(:embed, :es).related == Poster.Translations.Fields
    end

    test "translates", %{poster: poster} do
      assert Translate.translate(poster, :title, :es) == "Título"
      assert Translate.translate(poster, :es).body == "Cuerpo"
      assert Translate.translate(poster, :title, :fr) == "English title"
    end

    test "keeps the extra field", %{poster: poster} do
      assert poster.translations.es.reviewed == true
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _options} -> message end)
  end
end
