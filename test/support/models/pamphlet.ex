require Localize.Translate

defmodule Localize.Translate.Pamphlet do
  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en

  schema "magazine" do
    field(:title, :string)
    field(:body, :string)
    translations(:translations, Translations)
  end
end
