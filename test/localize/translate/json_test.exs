defmodule Localize.Translate.JSONTest do
  use ExUnit.Case, async: true

  alias Localize.Translate.Article
  alias Localize.Translate.JSON

  doctest Localize.Translate.JSON

  describe "encode!/1" do
    test "encodes a map to a binary" do
      assert JSON.encode!(%{"title" => "Título"}) == ~s({"title":"Título"})
    end

    test "encodes nil as JSON null" do
      assert JSON.encode!(nil) == "null"
    end

    test "encodes booleans" do
      assert JSON.encode!(true) == "true"
      assert JSON.encode!(false) == "false"
    end

    test "encodes nested nil and booleans inside a map" do
      encoded = JSON.encode!(%{"a" => nil, "b" => true, "c" => false})

      assert JSON.decode!(encoded) == %{"a" => nil, "b" => true, "c" => false}
    end

    test "encodes numbers, strings and lists" do
      assert JSON.encode!(1) == "1"
      assert JSON.encode!("text") == ~s("text")
      assert JSON.decode!(JSON.encode!([1, 2, 3])) == [1, 2, 3]
    end

    test "encodes a struct by dropping __struct__" do
      encoded = JSON.encode!(%Article.Translations.Fields{title: "Título", body: "Cuerpo"})
      decoded = JSON.decode!(encoded)

      assert decoded["title"] == "Título"
      assert decoded["body"] == "Cuerpo"
      refute Map.has_key?(decoded, "__struct__")
    end

    test "encodes a struct nested inside a map" do
      encoded = JSON.encode!(%{"es" => %Article.Translations.Fields{title: "Título"}})

      assert JSON.decode!(encoded)["es"]["title"] == "Título"
    end
  end

  describe "encode_to_iodata!/1" do
    test "returns iodata that flattens to the same binary as encode!/1" do
      value = %{"title" => "Título"}

      assert value |> JSON.encode_to_iodata!() |> IO.iodata_to_binary() == JSON.encode!(value)
    end
  end

  describe "decode!/1" do
    test "decodes a binary" do
      assert JSON.decode!(~s({"title":"Título"})) == %{"title" => "Título"}
    end

    test "decodes iodata" do
      assert JSON.decode!([~s({"title":), ~s("Título"})]) == %{"title" => "Título"}
    end

    test "decodes JSON null to nil rather than the :null atom" do
      assert JSON.decode!(~s({"title":null})) == %{"title" => nil}
    end

    test "round-trips a nested structure" do
      value = %{"es" => %{"title" => "Título", "tags" => ["a", "b"], "draft" => false}}

      assert value |> JSON.encode!() |> JSON.decode!() == value
    end
  end
end
