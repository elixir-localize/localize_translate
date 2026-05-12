defmodule Localize.Translate.Locale do
  @moduledoc false

  # Single entry point for locale handling. Every locale value (atom, string, or
  # `Localize.LanguageTag`) is validated via `Localize.validate_locale/1` and unwrapped
  # to its `:cldr_locale_id` atom. Fallback chains are constructed by walking
  # CLDR parent locales.
  #
  # Invalid locale names raise — by design. The library treats locale identifiers as a
  # bounded set defined by CLDR, not as free-form keys.

  alias Localize.LanguageTag

  @typedoc """
  Any value accepted as a locale: a `LanguageTag`, an atom, or a string. Lists of these
  are also accepted by `expand/1,2`.
  """
  @type input :: LanguageTag.t() | atom() | String.t()

  @doc """
  Returns the current locale as a `LanguageTag`.

  Thin wrapper over `Localize.get_locale/0` provided so internal callers don't pull in
  the `Localize` alias.
  """
  @spec current() :: LanguageTag.t()
  def current, do: Localize.get_locale()

  @doc """
  Validates `locale` and returns the canonical `:cldr_locale_id` atom.

  Raises `Localize.InvalidLocaleError` (or whatever exception
  `Localize.validate_locale/1` returns) if the input cannot be resolved to a CLDR
  locale.
  """
  @spec normalise!(input()) :: atom()
  def normalise!(locale) do
    locale |> validate!() |> Map.fetch!(:cldr_locale_id)
  end

  @doc """
  Expands `input` into a CLDR-aware locale fallback chain.

  Each input is validated and then walked up the CLDR parent chain (e.g. `:"en-AU"` →
  `:"en-001"` → `:en`, stopping before the `:und` root). Lists are flattened, validated
  per-element, and deduplicated in input order.

  When `supported` is a non-empty list, the chain is filtered to only those locales —
  use this to drop parents that the schema doesn't actually carry translations for.
  Pass `nil` (or an empty list) to skip filtering.

  Raises if any input is not a valid locale.
  """
  @spec expand(input() | [input()] | nil, [atom()] | nil) :: [atom()]
  def expand(input, supported \\ nil)

  def expand(nil, _supported), do: []

  def expand(input, supported) do
    input
    |> List.wrap()
    |> Enum.flat_map(&expand_one!/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> filter_supported(supported)
  end

  defp expand_one!(input) do
    tag = validate!(input)
    walk_parents(tag, [tag.cldr_locale_id])
  end

  defp validate!(input) do
    case Localize.validate_locale(input) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  # Stop at `und` (the CLDR root) without appending it — querying for `:und`
  # translations is meaningless and only adds noise to the fallback chain.
  defp walk_parents(%LanguageTag{language: :und}, acc), do: Enum.reverse(acc)

  defp walk_parents(%LanguageTag{} = tag, acc) do
    {:ok, parent} = Localize.Locale.parent(tag)

    case parent do
      %LanguageTag{language: :und} -> Enum.reverse(acc)
      _ -> walk_parents(parent, [derive_cldr_locale_id(parent) | acc])
    end
  end

  # `Localize.Locale.parent/1` returns a `LanguageTag` with the structural subtags
  # populated but `:cldr_locale_id` inherited from the child. Re-derive by
  # round-tripping the serialised form through `cldr_locale_id_from/1`, which
  # normalises e.g. `"fr-Latn"` to `:fr`.
  defp derive_cldr_locale_id(%LanguageTag{} = tag) do
    case Localize.Locale.cldr_locale_id_from(LanguageTag.to_string(tag)) do
      {:ok, id} -> id
      {:error, _} -> nil
    end
  end

  defp filter_supported(chain, nil), do: chain
  defp filter_supported(chain, []), do: chain
  defp filter_supported(chain, list) when is_list(list), do: Enum.filter(chain, &(&1 in list))
end
