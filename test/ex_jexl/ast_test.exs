defmodule ExJexl.ASTTest do
  use ExUnit.Case, async: true

  alias ExJexl.AST
  alias ExJexl.Parser

  describe "prewalk/3" do
    test "visits literal" do
      ast = {:integer, 42}
      {result_ast, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert result_ast == {:integer, 42}
      assert acc == [{:integer, 42}]
    end

    test "visits identifier" do
      ast = {:identifier, "x"}
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert acc == [{:identifier, "x"}]
    end

    test "visits array elements" do
      {:ok, ast} = Parser.parse("[1, 2, 3]")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:array, _} = List.last(acc)
      assert {:integer, 1} in acc
      assert {:integer, 2} in acc
      assert {:integer, 3} in acc
    end

    test "visits object pair values" do
      {:ok, ast} = Parser.parse(~s({"a": 1, "b": 2}))
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:integer, 1} in acc
      assert {:integer, 2} in acc
    end

    test "visits property access object" do
      {:ok, ast} = Parser.parse("user.name")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "user"} in acc
    end

    test "visits bracket access object and key" do
      {:ok, ast} = Parser.parse("data[idx]")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "data"} in acc
      assert {:identifier, "idx"} in acc
    end

    test "visits ternary branches" do
      {:ok, ast} = Parser.parse("x ? a : b")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "x"} in acc
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "visits binary_op children" do
      {:ok, ast} = Parser.parse("a + b")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "visits unary expression child" do
      {:ok, ast} = Parser.parse("!x")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "x"} in acc
    end

    test "visits function call args (not the head identifier)" do
      {:ok, ast} = Parser.parse("f(a, b)")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "transforms via the function" do
      {:ok, ast} = Parser.parse("x + 1")

      {new_ast, _} =
        AST.prewalk(ast, nil, fn
          {:integer, n}, a -> {{:integer, n + 100}, a}
          node, a -> {node, a}
        end)

      assert match?({:binary_op, [:+, {:identifier, "x"}, {:integer, 101}]}, new_ast)
    end
  end

  describe "postwalk/3" do
    test "visits children before parent" do
      {:ok, ast} = Parser.parse("a + b")
      {_, acc} = AST.postwalk(ast, [], fn node, a -> {node, [node | a]} end)
      visit_order = Enum.reverse(acc)
      [first | _] = visit_order
      assert first == {:identifier, "a"}
      [last | _] = acc
      assert match?({:binary_op, _}, last)
    end

    test "transforms bottom-up" do
      {:ok, ast} = Parser.parse("x + 1")

      {new_ast, _} =
        AST.postwalk(ast, nil, fn
          {:integer, n}, a -> {{:integer, n * 10}, a}
          node, a -> {node, a}
        end)

      assert match?({:binary_op, [:+, {:identifier, "x"}, {:integer, 10}]}, new_ast)
    end
  end

  describe "walk/3 (read-only fold)" do
    test "collects all identifiers" do
      {:ok, ast} = Parser.parse("a + b * c")

      ids =
        AST.walk(ast, [], fn
          {:identifier, name}, acc -> [name | acc]
          _, acc -> acc
        end)

      assert Enum.sort(ids) == ["a", "b", "c"]
    end

    test "counts integer literals" do
      {:ok, ast} = Parser.parse("[1, 2, 3]")

      count =
        AST.walk(ast, 0, fn
          {:integer, _}, acc -> acc + 1
          _, acc -> acc
        end)

      assert count == 3
    end
  end

  describe "find_transforms/2" do
    test "finds single transform with no args" do
      {:ok, ast} = Parser.parse("x|length")
      assert [match] = AST.find_transforms(ast, "length")
      assert match.name == "length"
      assert match.subject == {:identifier, "x"}
      assert match.args == []
    end

    test "finds transform with args" do
      {:ok, ast} = Parser.parse("q|answer(\"default\")")
      assert [match] = AST.find_transforms(ast, "answer")
      assert match.name == "answer"
      assert match.subject == {:identifier, "q"}
      assert match.args == [{:string, "default"}]
    end

    test "finds chained transforms" do
      {:ok, ast} = Parser.parse("a|x|y")
      matches = AST.find_transforms(ast, :any)
      names = Enum.map(matches, & &1.name)
      assert "x" in names
      assert "y" in names
      assert length(matches) == 2
    end

    test "subject of outer chain transform is inner pipe" do
      {:ok, ast} = Parser.parse("a|x|y")
      [_x_match, y_match] = AST.find_transforms(ast, :any) |> Enum.sort_by(& &1.name)
      assert match?({:binary_op, [:|, _, _]}, y_match.subject)
    end

    test "any filter returns all transforms" do
      {:ok, ast} = Parser.parse("a|x|y|z")
      assert AST.find_transforms(ast, :any) |> length() == 3
    end

    test "string filter returns only matching name" do
      {:ok, ast} = Parser.parse("a|x|y|x")
      matches = AST.find_transforms(ast, "x")
      assert length(matches) == 2
      assert Enum.all?(matches, &(&1.name == "x"))
    end

    test "list filter returns matching names" do
      {:ok, ast} = Parser.parse("a|x|y|z")
      matches = AST.find_transforms(ast, ["x", "z"])
      names = Enum.map(matches, & &1.name) |> Enum.sort()
      assert names == ["x", "z"]
    end

    test "no match returns empty list" do
      {:ok, ast} = Parser.parse("a|x")
      assert [] == AST.find_transforms(ast, "missing")
    end

    test "expression with no transforms" do
      {:ok, ast} = Parser.parse("a + b")
      assert [] == AST.find_transforms(ast, :any)
    end

    test "transform inside ternary is found" do
      {:ok, ast} = Parser.parse("c ? a|x : b|y")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["x", "y"]
    end

    test "transform inside array is found" do
      {:ok, ast} = Parser.parse("[a|x, b|y]")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["x", "y"]
    end

    test "transform inside function call is found" do
      {:ok, ast} = Parser.parse("f(a|x)")
      assert [match] = AST.find_transforms(ast, :any)
      assert match.name == "x"
    end

    test "default name filter is :any" do
      {:ok, ast} = Parser.parse("a|x|y")
      assert AST.find_transforms(ast) |> length() == 2
    end

    test "transform inside transform argument is found" do
      {:ok, ast} = Parser.parse("a|f(b|x)")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["f", "x"]
    end

    test "transform inside argument of transform with multiple args" do
      {:ok, ast} = Parser.parse("a|f(b|x, c|y)")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["f", "x", "y"]
    end

    test "transform deep in nested transform args" do
      {:ok, ast} = Parser.parse("a|f([b|x, c])")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["f", "x"]
    end
  end
end
