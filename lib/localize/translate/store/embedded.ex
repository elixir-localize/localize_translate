defmodule Localize.Translate.Store.Embedded do
  @moduledoc """
  The default translation store, keeping translations on the subject itself.

  Translations live in a single container field on the struct — a `jsonb`
  column for an Ecto schema — shaped as a map of locale to a map of field to
  value:

      %{
        "es" => %{"title" => "Título", "body" => "Cuerpo"},
        "fr" => %{"title" => "Titre"}
      }

  One row holds a record and all of its translations, so reading them costs no
  join and no second query. This is the storage model `Localize.Translate` has
  always used; the behaviour simply makes it swappable.

  Both string and atom keys are accepted at every level, because a struct
  loaded from the database carries string keys while one built in Elixir may
  carry atoms.

  This store is queryable: `Localize.Translate.QueryBuilder` pushes predicates
  into SQL against the container column.

  """

  @behaviour Localize.Translate.Store

  @impl Localize.Translate.Store
  def fetch_translation(%{__struct__: module} = subject, locale, field, _options \\ []) do
    with {:ok, all_translations} <- Map.fetch(subject, module.__trans__(:container)),
         {:ok, for_locale} <- fetch_locale(all_translations, locale),
         {:ok, value} <- fetch_field(for_locale, field) do
      {:ok, value}
    else
      _other -> :error
    end
  end

  @impl Localize.Translate.Store
  def put_translation(%{__struct__: module} = subject, locale, field, value, _options \\ []) do
    container = module.__trans__(:container)
    all_translations = Map.get(subject, container) || %{}
    key = locale_key(all_translations, locale)

    updated =
      all_translations
      |> Map.put_new(key, %{})
      |> Map.update!(key, &Map.put(&1, field_key(Map.get(all_translations, key), field), value))

    {:ok, Map.put(subject, container, updated)}
  end

  @impl Localize.Translate.Store
  def locales(%{__struct__: module} = subject, _options \\ []) do
    subject
    |> Map.get(module.__trans__(:container))
    |> case do
      nil ->
        []

      translations ->
        translations
        |> Map.keys()
        |> Enum.reject(&(&1 == :__struct__))
        |> Enum.map(&to_locale_atom/1)
    end
  end

  @impl Localize.Translate.Store
  def queryable?, do: true

  # A struct container keys by atom; a decoded jsonb map keys by string.
  defp fetch_locale(%{__struct__: _} = all_translations, locale) when is_binary(locale) do
    fetch_locale(all_translations, to_existing_atom(locale))
  end

  defp fetch_locale(%{__struct__: _} = all_translations, locale) when is_atom(locale) do
    Map.fetch(all_translations, locale)
  end

  defp fetch_locale(nil, _locale), do: :error

  defp fetch_locale(_all_translations, nil), do: :error

  defp fetch_locale(all_translations, locale) do
    Map.fetch(all_translations, to_string(locale))
  end

  defp fetch_field(nil, _field), do: :error

  defp fetch_field(%{__struct__: _} = for_locale, field) when is_binary(field) do
    fetch_field(for_locale, to_existing_atom(field))
  end

  defp fetch_field(%{__struct__: _} = for_locale, field) when is_atom(field) do
    Map.fetch(for_locale, field)
  end

  defp fetch_field(for_locale, field) do
    Map.fetch(for_locale, to_string(field))
  end

  # Write using whichever key style the container already uses, so a struct
  # container stays atom-keyed and a jsonb map stays string-keyed.
  defp locale_key(%{__struct__: _}, locale) when is_atom(locale), do: locale
  defp locale_key(%{__struct__: _}, locale), do: to_existing_atom(locale)
  defp locale_key(_all_translations, locale), do: to_string(locale)

  defp field_key(%{__struct__: _}, field) when is_atom(field), do: field
  defp field_key(%{__struct__: _}, field), do: to_existing_atom(field)
  defp field_key(_for_locale, field), do: to_string(field)

  # An unknown name has no existing atom, and therefore no translation, so it
  # resolves to the same miss without growing the atom table.
  defp to_existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp to_locale_atom(locale) when is_atom(locale), do: locale
  defp to_locale_atom(locale), do: to_existing_atom(locale)
end
