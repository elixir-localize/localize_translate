defmodule Localize.Translate.FlyerTranslationFields do
  @moduledoc """
  A caller's own per-locale schema: the translatable fields of
  `Localize.Translate.Flyer` and state kept beside them.

  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:title, :string)
    field(:body, :string)
    field(:translated_by, :string)
    field(:machine_translated, :boolean, default: false)
    field(:translated_at, :utc_datetime)
  end

  def changeset(fields, params) do
    fields
    |> cast(params, [:title, :body, :translated_by, :machine_translated, :translated_at])
    |> validate_required([:title])
  end
end

defmodule Localize.Translate.Flyer do
  @moduledoc """
  Fixture exercising the `:fields_module` option of the `translations/3` macro.

  The `Translations` schema is generated and each locale embeds
  `Localize.Translate.FlyerTranslationFields`; no `Fields` schema is generated.

  """

  use Ecto.Schema
  import Ecto.Changeset

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)

    translations(:translations, Translations,
      fields_module: Localize.Translate.FlyerTranslationFields
    )
  end

  def changeset(flyer, params) do
    flyer
    |> cast(params, [:title, :body])
    |> cast_embed(:translations, with: &translations_changeset/2)
  end

  defp translations_changeset(translations, params) do
    translations
    |> cast(params, [])
    |> cast_embed(:es)
    |> cast_embed(:fr)
  end
end
