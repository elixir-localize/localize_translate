defmodule Localize.Translate.Poster do
  @moduledoc """
  Fixture exercising `build_field_schema: false`: the macro declares the
  container embed and both schemas beneath it are written by hand.

  """

  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)

    translations(:translations, Translations, build_field_schema: false)
  end
end

defmodule Localize.Translate.Poster.Translations do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    embeds_one(:es, Localize.Translate.Poster.Translations.Fields, on_replace: :update)
    embeds_one(:fr, Localize.Translate.Poster.Translations.Fields, on_replace: :update)
  end
end

defmodule Localize.Translate.Poster.Translations.Fields do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:title, :string)
    field(:body, :string)
    field(:reviewed, :boolean, default: false)
  end
end
