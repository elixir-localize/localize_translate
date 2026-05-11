require Localize.Translate

defmodule Localize.Translate.Brochure do
  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :ar, :de, :doi, :"en-AU", :"fr-CA", :ja, :nb, :no, :pl, :th],
    default_locale: :en

  schema "articles" do
    field(:title, :string)
    field(:body, :string)
    translations(:translations)
  end
end
