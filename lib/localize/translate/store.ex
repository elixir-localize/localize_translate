defmodule Localize.Translate.Store do
  @moduledoc """
  Behaviour for translation storage backends.

  A store answers one question: given a subject, a locale and a field, what is
  the translated value? Everything else in `Localize.Translate` — locale
  validation, CLDR parent-chain fallback, the `translate/2,3` API — is built on
  top and is the same whichever store is in use.

  The default store is `Localize.Translate.Store.Embedded`, which keeps
  translations in a map on the subject itself. It is what this library has
  always done and remains the recommended choice for Ecto schemas.

  The behaviour is subject-and-field shaped rather than key-value shaped. A
  store receives the whole subject, not an extracted key, so it can resolve a
  translation from the subject's own data without a second read. That is what
  makes the embedded store possible at all, and it is why fallback chains can
  be evaluated without one round trip per candidate locale.

  ## Implementing a store

  A store is any module implementing this behaviour. Storage need not be a
  database — an in-memory map, ETS, or a file are all valid, because only the
  optional `c:queryable?/0` capability concerns databases.

      defmodule MyApp.EtsStore do
        @behaviour Localize.Translate.Store

        @impl true
        def fetch_translation(subject, locale, field, _options) do
          case :ets.lookup(:translations, {subject.id, locale, field}) do
            [{_key, value}] -> {:ok, value}
            [] -> :error
          end
        end

        @impl true
        def locales(subject, _options) do
          :ets.match(:translations, {{subject.id, :"$1", :_}, :_}) |> List.flatten()
        end

        @impl true
        def queryable?, do: false
      end

  Select it per schema:

      use Localize.Translate,
        translates: [:title, :body],
        store: MyApp.EtsStore

  ## Querying

  `c:queryable?/0` reports whether a store can push a translation predicate
  into the data layer. Only stores backed by a database can — filtering by
  translated text inside SQL has no meaning for an ETS or in-memory store, so
  it is a capability a store declares rather than a callback every store must
  implement.

  `Localize.Translate.QueryBuilder` requires a queryable store; it raises for
  any other, naming the store, rather than silently returning unfiltered rows.

  """

  @typedoc """
  The struct carrying translations.

  """
  @type subject :: struct()

  @typedoc """
  The name of a translatable field.

  """
  @type field :: atom()

  @typedoc """
  A validated locale.

  """
  @type locale :: atom()

  @doc """
  Fetches the translation of a single field.

  ### Arguments

  * `subject` is the struct holding the translations.

  * `locale` is a validated locale atom. Fallback is applied by the caller, so
    a store answers for exactly this locale.

  * `field` is the name of the translatable field.

  * `options` is a keyword list of store-specific options.

  ### Returns

  * `{:ok, value}` if a translation exists for this locale and field.

  * `:error` if none exists, so the caller can try the next locale in the
    fallback chain.

  """
  @callback fetch_translation(subject(), locale(), field(), options :: keyword()) ::
              {:ok, term()} | :error

  @doc """
  Writes the translation of a single field.

  Optional. A read-only store — one backed by a translation service, say — need
  not implement it.

  ### Arguments

  * `subject` is the struct holding the translations.

  * `locale` is a validated locale atom.

  * `field` is the name of the translatable field.

  * `value` is the translated value to store.

  * `options` is a keyword list of store-specific options.

  ### Returns

  * `{:ok, subject}` with the subject updated to carry the new translation.

  * `{:error, reason}` if the write failed.

  """
  @callback put_translation(subject(), locale(), field(), value :: term(), options :: keyword()) ::
              {:ok, subject()} | {:error, term()}

  @doc """
  Lists the locales for which the subject holds translations.

  ### Arguments

  * `subject` is the struct holding the translations.

  * `options` is a keyword list of store-specific options.

  ### Returns

  * A list of validated locale atoms, which may be empty.

  """
  @callback locales(subject(), options :: keyword()) :: [locale()]

  @doc """
  Returns whether the store can push translation predicates into the data layer.

  ### Returns

  * `true` if `Localize.Translate.QueryBuilder` can build query fragments
    against this store.

  * `false` otherwise, in which case filtering happens in Elixir after loading.

  """
  @callback queryable?() :: boolean()

  @optional_callbacks put_translation: 5
end
