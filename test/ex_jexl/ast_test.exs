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
      {new_ast, _} = AST.prewalk(ast, nil, fn
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
      {new_ast, _} = AST.postwalk(ast, nil, fn
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
end
