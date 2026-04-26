defmodule ExJexl.AST do
  @moduledoc """
  AST inspection utilities for ex_jexl expressions.

  The AST is the tuple-based intermediate representation produced by
  `ExJexl.Parser.parse/1`. This module provides walkers and helpers
  for downstream tooling — analyzers, validators, dependency extraction.

  ## AST format

      {:integer, integer}
      {:float, float}
      {:string, binary}
      {:boolean, boolean}
      {:null, nil}
      {:identifier, name :: binary}
      {:array, [{:integer | :float | ..., value}, ...]}
      {:object, [{:pair, [key_ast, value_ast]}, ...]}
      {:property_access, [obj_ast, {:identifier, prop}]}
      {:bracket_access, [obj_ast, key_ast]}
      {:ternary, [cond_ast, true_ast, false_ast]}
      {:binary_op, [op_atom, left_ast, right_ast]}
      {:unary, [{:op, :!}, expr_ast]}
      {:function_call, [{:identifier, name} | arg_asts]}

  Pipe / transform encoding: `a|x|y` parses left-associative as
  `{:binary_op, [:|, {:binary_op, [:|, a, x_call]}, y_call]}` where the
  transform call (the right side of each pipe) is either `{:identifier, name}`
  for a no-arg transform or `{:function_call, [{:identifier, name} | args]}`
  for a transform with arguments. Use `find_transforms/2` to abstract over
  this encoding.
  """

  @type ast :: tuple()

  @doc """
  Walks the AST in pre-order, applying `fun` to each node and threading `acc`.

  `fun` receives `(node, acc)` and returns `{node, acc}`. Mirrors `Macro.prewalk/3`.
  """
  @spec prewalk(ast, acc, (ast, acc -> {ast, acc})) :: {ast, acc} when acc: any
  def prewalk(ast, acc, fun) do
    {new_ast, new_acc} = fun.(ast, acc)
    walk_children(new_ast, new_acc, &prewalk(&1, &2, fun))
  end

  @doc """
  Walks the AST in post-order, applying `fun` to each node and threading `acc`.

  Children are visited before their parent. Useful for bottom-up transformations.
  """
  @spec postwalk(ast, acc, (ast, acc -> {ast, acc})) :: {ast, acc} when acc: any
  def postwalk(ast, acc, fun) do
    {new_ast, new_acc} = walk_children(ast, acc, &postwalk(&1, &2, fun))
    fun.(new_ast, new_acc)
  end

  @doc """
  Read-only fold over the AST in pre-order.

  `fun` receives `(node, acc)` and returns the new accumulator. Equivalent
  to `prewalk/3` with the node passed through unchanged.
  """
  @spec walk(ast, acc, (ast, acc -> acc)) :: acc when acc: any
  def walk(ast, acc, fun) do
    {_, final} = prewalk(ast, acc, fn n, a -> {n, fun.(n, a)} end)
    final
  end

  @doc """
  Find all transform applications in the AST.

  Returns a list of matches, one per transform call:

      %{name: String.t(), subject: ast, args: [ast]}

  The `name` filter accepts:
    * `:any` — every transform call (default)
    * `String.t()` — exact name match
    * `[String.t()]` — any name in the list

  Chained pipes (`a|x|y`) yield one match per transform; the subject of an
  outer transform is the inner pipe AST.
  """
  @spec find_transforms(ast, :any | String.t() | [String.t()]) :: [%{
          name: String.t(),
          subject: ast,
          args: [ast]
        }]
  def find_transforms(ast, name \\ :any)

  def find_transforms(ast, :any) do
    ast
    |> walk([], fn
      {:binary_op, [:|, subject, transform_call]}, acc ->
        case extract_transform_call(transform_call) do
          {:ok, n, args} -> [%{name: n, subject: subject, args: args} | acc]
          :error -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  def find_transforms(ast, name) when is_binary(name) do
    find_transforms(ast, [name])
  end

  def find_transforms(ast, names) when is_list(names) do
    ast
    |> find_transforms(:any)
    |> Enum.filter(fn %{name: n} -> n in names end)
  end

  defp extract_transform_call({:identifier, name}), do: {:ok, name, []}

  defp extract_transform_call({:function_call, [{:identifier, name} | args]}),
    do: {:ok, name, args}

  defp extract_transform_call(_), do: :error

  # walk_children dispatches on the outer tag of each AST node,
  # recursing into child nodes. Leaf nodes are returned unchanged.

  defp walk_children({:array, elements}, acc, walker) do
    {new_elements, acc} = Enum.map_reduce(elements, acc, walker)
    {{:array, new_elements}, acc}
  end

  defp walk_children({:object, pairs}, acc, walker) do
    {new_pairs, acc} =
      Enum.map_reduce(pairs, acc, fn {:pair, [k, v]}, a ->
        {new_v, a2} = walker.(v, a)
        {{:pair, [k, new_v]}, a2}
      end)

    {{:object, new_pairs}, acc}
  end

  defp walk_children({:property_access, [obj, prop]}, acc, walker) do
    {new_obj, acc} = walker.(obj, acc)
    {{:property_access, [new_obj, prop]}, acc}
  end

  defp walk_children({:bracket_access, [obj, key]}, acc, walker) do
    {new_obj, acc} = walker.(obj, acc)
    {new_key, acc} = walker.(key, acc)
    {{:bracket_access, [new_obj, new_key]}, acc}
  end

  defp walk_children({:ternary, [c, t, f]}, acc, walker) do
    {new_c, acc} = walker.(c, acc)
    {new_t, acc} = walker.(t, acc)
    {new_f, acc} = walker.(f, acc)
    {{:ternary, [new_c, new_t, new_f]}, acc}
  end

  defp walk_children({:binary_op, [op, l, r]}, acc, walker) do
    {new_l, acc} = walker.(l, acc)
    {new_r, acc} = walker.(r, acc)
    {{:binary_op, [op, new_l, new_r]}, acc}
  end

  defp walk_children({:unary, [op_tag, expr]}, acc, walker) do
    {new_expr, acc} = walker.(expr, acc)
    {{:unary, [op_tag, new_expr]}, acc}
  end

  defp walk_children({:function_call, [head | args]}, acc, walker) do
    {new_args, acc} = Enum.map_reduce(args, acc, walker)
    {{:function_call, [head | new_args]}, acc}
  end

  defp walk_children(leaf, acc, _walker), do: {leaf, acc}
end
