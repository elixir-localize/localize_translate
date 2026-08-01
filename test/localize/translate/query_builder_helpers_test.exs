defmodule Localize.Translate.QueryBuilderHelpersTest do
  @moduledoc """
  Covers the `QueryBuilder` helpers that are reachable outside a query.

  """

  use ExUnit.Case, async: true

  alias Localize.Translate.QueryBuilder

  describe "list_to_sql_array/1,2" do
    test "expands a locale into a list of strings without a supported-locale filter" do
      assert QueryBuilder.list_to_sql_array(:es) == ["es"]
    end

    test "accepts a locale given as a string" do
      assert QueryBuilder.list_to_sql_array("es") == ["es"]
    end

    test "expands a list of locales" do
      assert QueryBuilder.list_to_sql_array([:es, :fr]) == ["es", "fr"]
    end

    test "expands a locale through its CLDR parent chain" do
      assert "en" in QueryBuilder.list_to_sql_array(:"en-AU")
    end

    test "filters the expansion to the supported locales" do
      assert QueryBuilder.list_to_sql_array(:"en-AU", [:en]) == ["en"]
    end
  end
end
