defmodule Localize.Translate.Repo.Migrations.AddSiblingTranslationsTable do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :title, :string
      add :body, :string
    end

    create table(:page_translations) do
      add :locale, :string, null: false
      add :title, :string
      add :body, :string
      add :page_id, references(:pages, on_delete: :delete_all), null: false
    end

    # Without this, nothing stops two rows claiming the same translation.
    create unique_index(:page_translations, [:page_id, :locale])
  end
end
