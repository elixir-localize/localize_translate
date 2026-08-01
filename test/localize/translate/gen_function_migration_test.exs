defmodule Localize.Translate.GenFunctionMigrationTest do
  @moduledoc """
  Covers the helpers of the `localize.translate.gen.translate_function` mix task.

  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Localize.Translate.Gen.TranslateFunction

  describe "format_string!/1" do
    test "returns a binary rather than iodata" do
      assert is_binary(TranslateFunction.format_string!("x=1"))
    end

    test "formats the source it is given" do
      assert TranslateFunction.format_string!("x=1") == "x = 1"
    end

    test "leaves already-formatted source unchanged" do
      formatted = "x = 1"

      assert TranslateFunction.format_string!(formatted) == formatted
    end

    test "formats a multi-line module definition" do
      source = """
      defmodule   Foo do
      def   bar,   do:   :ok
      end
      """

      formatted = TranslateFunction.format_string!(source)

      assert formatted =~ "defmodule Foo do"
      assert formatted =~ "def bar, do: :ok"
    end
  end

  describe "migrations_path/1" do
    test "returns a migrations path for a repo" do
      path = TranslateFunction.migrations_path(Localize.Translate.Repo)

      assert is_binary(path)
      assert String.ends_with?(path, "migrations")
    end
  end

  describe "task metadata" do
    test "is registered as a mix task with a short description" do
      # `function_exported?/3` answers false for a module that is merely
      # compiled but not yet loaded, so load it first — otherwise this passes
      # or fails depending on test order.
      Code.ensure_loaded!(TranslateFunction)

      assert function_exported?(TranslateFunction, :run, 1)
      assert Mix.Task.shortdoc(TranslateFunction) =~ "translate_field"
    end
  end
end
