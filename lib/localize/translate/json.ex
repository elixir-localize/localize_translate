defmodule Localize.Translate.JSON do
  @moduledoc """
  Adapter that exposes the Erlang `:json` module under the bang-suffixed API
  (`encode!/1`, `decode!/1`, `encode_to_iodata!/1`) expected by Ecto and Postgrex.

  Provides Elixir-native semantics on top of `:json`:

  * `nil` encodes as JSON `null` (not the string `"nil"`).
  * `true` and `false` encode as JSON booleans.
  * Structs encode as maps (the `:__struct__` key is dropped).
  * Other atoms encode as strings.

  Configure Ecto and Postgrex to use it via:

      config :ecto, json_library: Localize.Translate.JSON
      config :postgrex, json_library: Localize.Translate.JSON
  """

  @spec encode!(term()) :: binary()
  def encode!(value), do: value |> encode_to_iodata!() |> IO.iodata_to_binary()

  @spec encode_to_iodata!(term()) :: iodata()
  def encode_to_iodata!(value), do: :json.encode(value, &encoder/2)

  @spec decode!(iodata()) :: term()
  def decode!(value) when is_binary(value), do: do_decode(value)
  def decode!(value), do: value |> IO.iodata_to_binary() |> do_decode()

  defp do_decode(binary) do
    {decoded, :ok, ""} = :json.decode(binary, :ok, %{null: nil})
    decoded
  end

  defp encoder(nil, _encode), do: ~c"null"
  defp encoder(true, _encode), do: ~c"true"
  defp encoder(false, _encode), do: ~c"false"

  defp encoder(%_{} = struct, encode) do
    struct |> Map.from_struct() |> encoder(encode)
  end

  defp encoder(value, encode), do: :json.encode_value(value, encode)
end
