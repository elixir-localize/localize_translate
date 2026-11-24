defmodule Localize.Translate.Locale do
  @moduledoc false

  # Single entry point for locale handling. Every locale value (atom, string, or
  # `Localize.LanguageTag`) is validated via `Localize.validate_locale/1` and unwrapped
  # to its `:cldr_locale_id` atom. Fallback chains are constructed by walking
  # CLDR parent locales.
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
  Validates `locale` and returns the canonical `:cldr_locale_id` atom.

  Raises `Localize.InvalidLocaleError` (or whatever exception
  `Localize.validate_locale/1` returns) if the input cannot be resolved to a CLDR
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
  Validates `locale` and returns its canonical `:cldr_locale_id` atom.

  Returns `{:ok, locale_id}`, or `{:error, exception}` when `locale` (including `nil`) is
  not a valid locale or resolves to the CLDR root, `und`.
  """
  @spec normalise(input() | nil) :: {:ok, atom()} | {:error, Exception.t()}
  def normalise(nil) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: "nil")}
  end

  def normalise(locale) do
    case Localize.validate_locale(locale) do
      {:ok, %LanguageTag{cldr_locale_id: :und}} -> no_cldr_data(locale)
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      {:error, _exception} = error -> error
    end
  end

  # A locale CLDR has no data for resolves to the root, `und`. Every such locale would
  # share that one key, so it is not a locale translations can be stored or read under.
  defp no_cldr_data(locale) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(locale))}
  end

  @doc """
  Expands `input` into a CLDR-aware locale fallback chain.

  Each input is validated and then walked up the CLDR parent chain (e.g. `:"en-AU"` →
  `:"en-001"` → `:en`, stopping before the `:und` root). Lists are flattened, validated
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

  # `nil` is refused here rather than left to `Localize.validate_locale/1`, which before
  # localize 1.10 read it as the language subtag `nil`.
  defp expand_one(nil) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: "nil")}
  end

  # A locale that resolves to the root, `und`, has no CLDR data and contributes nothing
  # to a chain, as the root itself does not.
  defp expand_one(input) do
    case Localize.validate_locale(input) do
      {:ok, %LanguageTag{cldr_locale_id: :und}} -> {:ok, []}
      {:ok, tag} -> {:ok, walk_parents(tag, [tag.cldr_locale_id])}
      {:error, _exception} = error -> error
    end
  end

  # Stop at `und` (the CLDR root) without appending it — querying for `:und`
  # translations is meaningless and only adds noise to the fallback chain.
  defp walk_parents(%LanguageTag{language: :und}, acc) do
    Enum.reverse(acc)
  end

  defp walk_parents(%LanguageTag{} = tag, acc) do
    case Localize.Locale.parent(tag) do
      {:ok, %LanguageTag{language: :und}} -> Enum.reverse(acc)
      {:ok, parent} -> walk_parents(parent, [derive_cldr_locale_id(parent) | acc])
      {:error, _exception} -> Enum.reverse(acc)
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
