defmodule Localize.Translate.Book.Translations.Fields do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:title, :string)
    field(:body, :string)
  end
end

defmodule Localize.Translate.Book do
  @moduledoc """
  The same as Article, but declares a default locale and used only for testing default locale and
  locale fallbacks.
  """

  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr, :it],
    default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)

    embeds_one :translations, Translations, on_replace: :update, primary_key: false do
      embeds_one(:es, __MODULE__.Fields, on_replace: :update)
      embeds_one(:fr, __MODULE__.Fields, on_replace: :update)
      embeds_one(:it, __MODULE__.Fields, on_replace: :update)
    end
  end
end
