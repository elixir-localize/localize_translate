defmodule Localize.Translate.StoreTest do
  use ExUnit.Case, async: true

  # A store shared by schemas kept in different places answers `queryable?/1` per
  # schema, here from the options each schema declares for it.
  defmodule PerSchemaStore do
    @moduledoc false
    @behaviour Localize.Translate.Store

    @impl true
    def fetch_translation(_subject, _locale, _field, _options) do
      :error
    end

    @impl true
    def locales(_subject, _options) do
      []
    end

    @impl true
    def queryable?(schema) do
      Keyword.get(schema.__trans__(:store_options), :data_layer) == :postgres
    end
  end

  defmodule PostgresNote do
    @moduledoc false
    use Ecto.Schema

    use Localize.Translate,
      translates: [:title],
      store: {PerSchemaStore, data_layer: :postgres}

    embedded_schema do
      field(:title, :string)
      field(:translations, :map)
    end
  end

  defmodule EtsNote do
    @moduledoc false
    use Ecto.Schema

    use Localize.Translate,
      translates: [:title],
      store: {PerSchemaStore, data_layer: :ets}

    embedded_schema do
      field(:title, :string)
      field(:translations, :map)
    end
  end

  defmodule Unreachable do
    defexception message: "the translation service is unreachable"
  end

  # A read-only store backed by a service that is down for French, has no German, and
  # has Spanish.
  defmodule ServiceStore do
    @moduledoc false
    @behaviour Localize.Translate.Store

    @impl true
    def fetch_translation(_subject, :fr, _field, _options) do
      {:error, %Unreachable{}}
    end

    def fetch_translation(_subject, :es, :title, _options) do
      {:ok, "Título"}
    end

    def fetch_translation(_subject, _locale, _field, _options) do
      :error
    end

    @impl true
    def locales(_subject, _options) do
      [:es]
    end

    @impl true
    def queryable?(_schema) do
      false
    end
  end

  defmodule ServiceNote do
    @moduledoc false
    use Ecto.Schema

    use Localize.Translate,
      translates: [:title],
      store: ServiceStore

    embedded_schema do
      field(:title, :string)
      field(:translations, :map)
    end
  end

  defp note do
    %ServiceNote{title: "Title"}
  end

  describe "a store that returns {:error, exception}" do
    test "translate/3 returns the base value" do
      assert Localize.Translate.translate(note(), :title, :fr) == "Title"
    end

    test "translate/3 stops the chain rather than trying the next locale" do
      assert Localize.Translate.translate(note(), :title, [:fr, :es]) == "Title"
    end

    test "translate/3 passes over a missing translation to the next locale" do
      assert Localize.Translate.translate(note(), :title, [:de, :es]) == "Título"
    end

    test "translate/2 keeps the base value of the field" do
      assert Localize.Translate.translate(note(), :fr).title == "Title"
      assert Localize.Translate.translate(note(), [:de, :es]).title == "Título"
    end

    test "translate!/3 raises the store's exception" do
      assert_raise Unreachable, "the translation service is unreachable", fn ->
        Localize.Translate.translate!(note(), :title, [:fr, :es])
      end
    end

    test "translate!/3 still raises a RuntimeError for a missing translation" do
      assert_raise RuntimeError, fn ->
        Localize.Translate.translate!(note(), :title, :de)
      end
    end
  end

  describe "queryable?/1" do
    test "a store answers for the schema it is given" do
      assert PerSchemaStore.queryable?(PostgresNote)
      refute PerSchemaStore.queryable?(EtsNote)
    end

    test "QueryBuilder accepts the schema the store is queryable for" do
      schema = PostgresNote

      query =
        quote do
          defmodule PostgresNoteQuery do
            import Ecto.Query, only: [from: 2]
            import Localize.Translate.QueryBuilder

            def query do
              from(n in unquote(schema),
                where: translated(unquote(schema), n.title, :es) == "Nota"
              )
            end
          end
        end

      assert {{:module, _module, _binary, _}, _binding} = Code.eval_quoted(query)
    end

    test "QueryBuilder refuses the schema the store is not queryable for" do
      schema = EtsNote

      query =
        quote do
          defmodule EtsNoteQuery do
            import Ecto.Query, only: [from: 2]
            import Localize.Translate.QueryBuilder

            def query do
              from(n in unquote(schema),
                where: translated(unquote(schema), n.title, :es) == "Nota"
              )
            end
          end
        end

      error = assert_raise ArgumentError, fn -> Code.eval_quoted(query) end

      assert error.message =~ "cannot be queried in SQL"
    end
  end
end
