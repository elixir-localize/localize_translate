defmodule Localize.Translate.Locale do
  @moduledoc false

  # Single entry point for locale handling. Every locale value (atom, string, or
  # `Localize.LanguageTag`) is resolved by `Localize.Locale.fallback_chain/1`: the CLDR
  # locale it names, and that locale's parents. Both are independent of the locales
  # Localize is configured for, so a translation is stored and read under the locale it
  # was given for: with only `en` and `fr` configured, `pt-BR` is `:pt`, where
  # `Localize.validate_locale/1` would negotiate it to `:en`.
  #
  # Locale identifiers are a bounded set defined by CLDR, not free-form keys, so every
  # input is validated. An invalid one is never raised at runtime: `expand/2` returns it
  # as an error, and `expand_valid/2` leaves it out of the chain. Only `normalise!/1`,
  # which validates schema options at compile time, raises.

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
  def current do
    Localize.get_locale()
  end

  @doc """
  Validates `locale` and returns the CLDR locale it names, as an atom.

  Raises `Localize.InvalidLocaleError` (or whatever exception
  `Localize.Locale.fallback_chain/1` returns) if the input cannot be resolved to a CLDR
  locale.
  """
  @spec normalise!(input()) :: atom()
  def normalise!(locale) do
    case normalise(locale) do
      {:ok, locale_id} -> locale_id
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Validates `locale` and returns the CLDR locale it names, as an atom: the first locale
  of its fallback chain, whatever locales Localize is configured for.

  Returns `{:ok, locale_id}`, or `{:error, exception}` when `locale` (including `nil`) is
  not a valid locale or resolves to the CLDR root, `und`.
  """
  @spec normalise(input() | nil) :: {:ok, atom()} | {:error, Exception.t()}
  def normalise(locale) do
    case Localize.Locale.fallback_chain(locale) do
      {:ok, [locale_id | _parents]} -> {:ok, locale_id}
      {:ok, []} -> no_cldr_data(locale)
      {:error, _exception} = error -> error
    end
  end

  # A locale CLDR has no data for resolves to the root, `und`, whose chain is empty.
  # Every such locale would share that one key, so it is not a locale translations can
  # be stored or read under.
  defp no_cldr_data(locale) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(locale))}
  end

  @doc """
  Expands `input` into a CLDR-aware locale fallback chain.

  Each input is resolved to its CLDR locale and that locale's parents by
  `Localize.Locale.fallback_chain/1` (e.g. `:"en-AU"` → `:"en-001"` → `:en`, stopping
  before the `:und` root), whatever locales Localize is configured for. Lists are flattened, validated
  per-element, and deduplicated in input order.

  When `supported` is a non-empty list, the chain is filtered to only those locales —
  use this to drop parents that the schema doesn't actually carry translations for.
  Pass `nil` (or an empty list) to skip filtering.

  Returns `{:ok, chain}`, or `{:error, exception}` for the first input that is not a
  valid locale. `nil` is not a locale, alone or in a list.
  """
  @spec expand(input() | [input()] | nil, [atom()] | nil) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def expand(input, supported \\ nil) do
    input
    |> wrap_input()
    |> Enum.reduce_while({:ok, []}, &expand_into/2)
    |> finish_chain(supported)
  end

  @doc """
  Expands `input` into a fallback chain as `expand/2` does, leaving out every input that
  is not a valid locale.

  An invalid locale has no translations, so leaving it out gives the same result as
  looking it up: the chain moves on to the next locale, or to the base value when none
  is left. Use this where a locale comes from a request and the caller wants a value,
  not an error.
  """
  @spec expand_valid(input() | [input()] | nil, [atom()] | nil) :: [atom()]
  def expand_valid(input, supported \\ nil)

  def expand_valid(nil, _supported) do
    []
  end

  def expand_valid(input, supported) do
    input
    |> List.wrap()
    |> Enum.flat_map(&valid_chain/1)
    |> build_chain(supported)
  end

  # `List.wrap(nil)` is `[]`, which would let a bare `nil` through as an empty chain.
  defp wrap_input(nil) do
    [nil]
  end

  defp wrap_input(input) do
    List.wrap(input)
  end

  defp expand_into(input, {:ok, chains}) do
    case expand_one(input) do
      {:ok, chain} -> {:cont, {:ok, [chain | chains]}}
      {:error, _exception} = error -> {:halt, error}
    end
  end

  defp finish_chain({:ok, chains}, supported) do
    chain =
      chains
      |> Enum.reverse()
      |> Enum.concat()
      |> build_chain(supported)

    {:ok, chain}
  end

  defp finish_chain({:error, _exception} = error, _supported) do
    error
  end

  defp valid_chain(input) do
    case expand_one(input) do
      {:ok, chain} -> chain
      {:error, _exception} -> []
    end
  end

  defp build_chain(chain, supported) do
    chain
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> filter_supported(supported)
  end

  # A locale that resolves to the root, `und`, has no CLDR data and contributes nothing
  # to a chain, as the root itself does not: its fallback chain is empty. `nil` is not a
  # locale, and is an error.
  defp expand_one(input) do
    Localize.Locale.fallback_chain(input)
  end

  defp filter_supported(chain, nil) do
    chain
  end

  defp filter_supported(chain, []) do
    chain
  end

  defp filter_supported(chain, list) when is_list(list) do
    Enum.filter(chain, &(&1 in list))
  end
end
