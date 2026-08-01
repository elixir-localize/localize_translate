defmodule Localize.Translate.PageTranslation do
  @moduledoc """
  Sibling translation rows for `Localize.Translate.Page`.

  """

  use Ecto.Schema

  schema "page_translations" do
    field(:locale, :string)
    field(:title, :string)
    field(:body, :string)

    belongs_to(:page, Localize.Translate.Page)
  end
end
