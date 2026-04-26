defmodule ExJexl.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExJexl.Validator

  describe "validate/2" do
    test "no validators returns ok with empty errors" do
      assert {:ok, []} = Validator.validate("1 + 1")
    end

    test "parse failure returns error tuple" do
      assert {:error, _reason} = Validator.validate("1 + + 2")
    end

    test "single validator with no errors" do
      validator = fn _ast -> [] end
      assert {:ok, []} = Validator.validate("1 + 1", [validator])
    end

    test "single validator with errors" do
      validator = fn _ast -> ["always wrong"] end
      assert {:ok, ["always wrong"]} = Validator.validate("1 + 1", [validator])
    end

    test "multiple validators concat errors" do
      v1 = fn _ -> ["e1"] end
      v2 = fn _ -> ["e2", "e3"] end
      assert {:ok, ["e1", "e2", "e3"]} = Validator.validate("1 + 1", [v1, v2])
    end

    test "validator can use AST.find_transforms to inspect expression" do
      validator = fn ast ->
        ast
        |> ExJexl.AST.find_transforms("answer")
        |> Enum.reject(fn %{subject: subject} -> match?({:string, _}, subject) end)
        |> Enum.map(fn _ -> "answer subject must be a string slug" end)
      end

      assert {:ok, []} = Validator.validate("'q'|answer", [validator])

      assert {:ok, ["answer subject must be a string slug"]} =
               Validator.validate("x|answer", [validator])
    end
  end

  describe "validate_ast/2" do
    test "runs validators against parsed AST" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      assert [] == Validator.validate_ast(ast, [])
    end

    test "no validators returns empty list" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      assert [] == Validator.validate_ast(ast)
    end

    test "collects errors from all validators" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      v1 = fn _ -> ["a"] end
      v2 = fn _ -> ["b"] end
      assert ["a", "b"] == Validator.validate_ast(ast, [v1, v2])
    end
  end
end
