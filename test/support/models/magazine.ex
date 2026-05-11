require Localize.Translate

defmodule Localize.Translate.Magazine do
  use Ecto.Schema
  use Localize.Translate, translates: [:title, :body], default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)
    translations(:translations, Translations, [:es, :it, :de])
  end
end
