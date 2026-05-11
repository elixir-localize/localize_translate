defmodule Localize.Translate.Comment do
  @moduledoc false

  use Ecto.Schema

  use Localize.Translate,
    translates: [:comment],
    container: :transcriptions,
    locales: [:en, :es, :fr],
    default_locale: :en

  import Ecto.Changeset

  schema "comments" do
    field(:comment, :string)
    field(:transcriptions, :map)
    belongs_to(:article, Localize.Translate.Article)
  end

  def changeset(comment, params \\ %{}) do
    comment
    |> cast(params, [:comment, :transcriptions])
    |> validate_required([:comment])
  end
end
