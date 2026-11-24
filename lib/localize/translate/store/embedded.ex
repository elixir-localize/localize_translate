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
         {:ok, for_locale} <- fetch_locale(all_translations, locale) do
      fetch_field(for_locale, field)
    end
  end

  @impl Localize.Translate.Store
  def put_translation(%{__struct__: module} = subject, locale, field, value, _options \\ []) do
    container = module.__trans__(:container)
    all_translations = Map.get(subject, container)

    with {:ok, updated} <- put_in_container(all_translations, locale, field, value) do
      {:ok, Map.put(subject, container, updated)}
    end
  end

  @impl Localize.Translate.Store
  def locales(%{__struct__: module} = subject, _options \\ []) do
    subject
    |> Map.get(module.__trans__(:container))
    |> container_locales()
  end

  @impl Localize.Translate.Store
  def queryable? do
    true
  end

  # A struct container keys by atom; a decoded jsonb map keys by string. A container,
  # or a locale's entry, that is not a map holds no translations: a jsonb column can
  # hold any JSON value, so these read as a miss rather than raise.
  defp fetch_locale(%{__struct__: _} = all_translations, locale) when is_binary(locale) do
    fetch_locale(all_translations, to_existing_atom(locale))
  end

  defp fetch_locale(%{__struct__: _} = all_translations, locale) when is_atom(locale) do
    Map.fetch(all_translations, locale)
  end

  defp fetch_locale(all_translations, locale)
       when is_map(all_translations) and not is_nil(locale) and
              (is_atom(locale) or is_binary(locale)) do
    Map.fetch(all_translations, to_string(locale))
  end

  defp fetch_locale(_all_translations, _locale) do
    :error
  end

  defp fetch_field(%{__struct__: _} = for_locale, field) when is_binary(field) do
    fetch_field(for_locale, to_existing_atom(field))
  end

  defp fetch_field(%{__struct__: _} = for_locale, field) when is_atom(field) do
    Map.fetch(for_locale, field)
  end

  defp fetch_field(for_locale, field)
       when is_map(for_locale) and not is_nil(field) and (is_atom(field) or is_binary(field)) do
    Map.fetch(for_locale, to_string(field))
  end

  defp fetch_field(_for_locale, _field) do
    :error
  end

  # Writes use whichever key style the container already uses, so a struct container
  # stays atom-keyed and a jsonb map stays string-keyed.
  defp put_in_container(nil, locale, field, value) do
    put_in_container(%{}, locale, field, value)
  end

  defp put_in_container(all_translations, locale, field, value) when is_map(all_translations) do
    with {:ok, locale_key} <- write_key(all_translations, locale, :locale),
         {:ok, for_locale} <- writable_locale(Map.get(all_translations, locale_key), locale),
         {:ok, field_key} <- write_key(for_locale, field, :field) do
      {:ok, Map.put(all_translations, locale_key, Map.put(for_locale, field_key, value))}
    end
  end

  defp put_in_container(all_translations, _locale, _field, _value) do
    write_error("the translation container is not a map: #{inspect(all_translations)}")
  end

  # A struct only takes the keys it defines: an unknown locale or field is refused
  # rather than added as a stray key.
  defp write_key(%{__struct__: _} = struct, key, kind) do
    atom_key = struct_key(key)

    if atom_key != :__struct__ and Map.has_key?(struct, atom_key) do
      {:ok, atom_key}
    else
      write_error("#{inspect(struct.__struct__)} has no #{kind} #{inspect(key)}")
    end
  end

  defp write_key(_map, key, _kind) when is_binary(key) and key != "" do
    {:ok, key}
  end

  defp write_key(_map, key, _kind) when is_atom(key) and not is_nil(key) and key != :"" do
    {:ok, Atom.to_string(key)}
  end

  defp write_key(_map, key, kind) do
    write_error("#{inspect(key)} is not a valid #{kind} name")
  end

  defp struct_key(key) when is_atom(key) do
    key
  end

  defp struct_key(key) when is_binary(key) do
    to_existing_atom(key)
  end

  defp struct_key(_key) do
    nil
  end

  defp writable_locale(nil, _locale) do
    {:ok, %{}}
  end

  defp writable_locale(for_locale, _locale) when is_map(for_locale) do
    {:ok, for_locale}
  end

  defp writable_locale(for_locale, locale) do
    write_error("the translations for #{inspect(locale)} are not a map: #{inspect(for_locale)}")
  end

  defp write_error(message) do
    {:error, ArgumentError.exception(message)}
  end

  defp container_locales(%{__struct__: _} = translations) do
    translations
    |> Map.keys()
    |> Enum.reject(&(&1 == :__struct__))
  end

  defp container_locales(translations) when is_map(translations) do
    translations
    |> Map.keys()
    |> Enum.map(&locale_atom/1)
    |> Enum.reject(&is_nil/1)
  end

  defp container_locales(_translations) do
    []
  end

  defp locale_atom(locale) when is_binary(locale) do
    to_existing_atom(locale)
  end

  defp locale_atom(locale) when is_atom(locale) do
    locale
  end

  defp locale_atom(_locale) do
    nil
  end

  # An unknown name has no existing atom, and therefore no translation, so it
  # resolves to the same miss without growing the atom table. `String.to_existing_atom/1`
  # has no non-raising form, so this is the one rescue in the store.
  defp to_existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
