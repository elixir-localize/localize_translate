defmodule Localize.Translate.Leaflet do
  @moduledoc """
  Fixture exercising the `translations/1,2,3` macro.

  The other fixtures declare their container with an explicit `embeds_one` block.
  This one uses the macro, so the generated `Translations` and
  `Translations.Fields` schemas are exercised too.

  """

  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)

    translations(:translations)
  end
end
