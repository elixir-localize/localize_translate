defmodule Localize.Translate.Page do
  @moduledoc """
  Fixture for the sibling-resource store.

  Its translations live in `page_translations`, one row per locale, and the
  container field is virtual — populated by the store on load.

  """

  use Ecto.Schema

  use Localize.Translate,
    translates: [:title, :body],
    locales: [:en, :es, :fr],
    default_locale: :en,
    store:
      {Localize.Translate.Store.SiblingResource,
       repo: Localize.Translate.Repo,
       schema: Localize.Translate.PageTranslation,
       foreign_key: :page_id}

  schema "pages" do
    field(:title, :string)
    field(:body, :string)
    field(:translations, :map, virtual: true)

    has_many(:page_translations, Localize.Translate.PageTranslation)
  end
end
