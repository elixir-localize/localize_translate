defmodule Localize.Translate.JSON do
  @moduledoc """
  Adapter that exposes the Erlang `:json` module under the bang-suffixed API
  (`encode!/1`, `decode!/1`, `encode_to_iodata!/1`) expected by Ecto and Postgrex.

  Provides Elixir-native semantics on top of `:json`:

  * `nil` encodes as JSON `null` (not the string `"nil"`).

  * `true` and `false` encode as JSON booleans.

  * `Date`, `Time`, `NaiveDateTime` and `DateTime` encode as ISO 8601 strings and a
    `Decimal` as its text, which is the form Ecto reads back into an embedded schema's
    `:date`, `:utc_datetime` and `:decimal` fields.

  * Other structs encode as maps (the `:__struct__` key is dropped).

  * Other atoms encode as strings.

  * JSON `null` decodes as `nil` (not the atom `:null`).

  Configured by default in `config/config.exs`:

      config :ecto, json_library: Localize.Translate.JSON
      config :postgrex, json_library: Localize.Translate.JSON

  """

  @doc """
  Encodes an Elixir term as a JSON binary.

  ### Arguments

  * `value` is any term encodable as JSON: a map, list, struct, binary, number, boolean,
    `nil`, or atom.

  ### Returns

  * A binary containing the JSON encoding of `value`.

  ### Examples

      iex> Localize.Translate.JSON.encode!(%{name: "Ada"})
      ~s({"name":"Ada"})

      iex> Localize.Translate.JSON.encode!([1, true, nil])
      "[1,true,null]"

      iex> Localize.Translate.JSON.encode!(nil)
      "null"

      iex> Localize.Translate.JSON.encode!(%{at: ~U[2026-11-23 10:00:00Z]})
      ~s({"at":"2026-11-23T10:00:00Z"})

  """
  @spec encode!(term()) :: binary()
  def encode!(value) do
    value
    |> encode_to_iodata!()
    |> IO.iodata_to_binary()
  end

  @doc """
  Encodes an Elixir term as JSON iodata.

  Identical to `encode!/1` but returns iodata for efficient writing to IO devices or
  sockets without an intermediate binary.

  ### Arguments

  * `value` is any term encodable as JSON.

  ### Returns

  * An iodata value (a binary, a list of binaries, or a list of iodata) containing the JSON
    encoding of `value`.

  ### Examples

      iex> %{}
      ...> |> Localize.Translate.JSON.encode_to_iodata!()
      ...> |> IO.iodata_to_binary()
      "{}"

  """
  @spec encode_to_iodata!(term()) :: iodata()
  def encode_to_iodata!(value) do
    :json.encode(value, &encoder/2)
  end

  @doc """
  Decodes a JSON binary into an Elixir term.

  ### Arguments

  * `value` is JSON-encoded iodata: a binary or a list of binaries.

  ### Returns

  * The decoded Elixir term. Objects decode as maps with string keys, arrays as lists,
    JSON `null` as `nil`, and JSON booleans as `true` / `false`.

  ### Examples

      iex> Localize.Translate.JSON.decode!(~s({"name":"Ada"}))
      %{"name" => "Ada"}

      iex> Localize.Translate.JSON.decode!("[1,true,null]")
      [1, true, nil]

  """
  @spec decode!(iodata()) :: term()
  def decode!(value) when is_binary(value) do
    do_decode(value)
  end

  def decode!(value) do
    value
    |> IO.iodata_to_binary()
    |> do_decode()
  end

  defp do_decode(binary) do
    {decoded, :ok, ""} = :json.decode(binary, :ok, %{null: nil})
    decoded
  end

  defp encoder(nil, _encode) do
    ~c"null"
  end

  defp encoder(true, _encode) do
    ~c"true"
  end

  defp encoder(false, _encode) do
    ~c"false"
  end

  defp encoder(%DateTime{} = value, encode) do
    encoder(DateTime.to_iso8601(value), encode)
  end

  defp encoder(%NaiveDateTime{} = value, encode) do
    encoder(NaiveDateTime.to_iso8601(value), encode)
  end

  defp encoder(%Date{} = value, encode) do
    encoder(Date.to_iso8601(value), encode)
  end

  defp encoder(%Time{} = value, encode) do
    encoder(Time.to_iso8601(value), encode)
  end

  defp encoder(%Decimal{} = value, encode) do
    encoder(Decimal.to_string(value), encode)
  end

  defp encoder(%_{} = struct, encode) do
    struct
    |> Map.from_struct()
    |> encoder(encode)
  end

  defp encoder(value, encode) do
    :json.encode_value(value, encode)
  end
end
