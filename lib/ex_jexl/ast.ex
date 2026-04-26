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
      {:array, [ast]}
      {:object, [{:pair, [key_ast, value_ast]}, ...]}
      {:property_access, [obj_ast, {:identifier, prop}]}
      {:bracket_access, [obj_ast, key_ast]}
      {:ternary, [cond_ast, true_ast, false_ast]}
      {:binary_op, [op_atom, left_ast, right_ast]}
      {:unary, [{:op, :!}, expr_ast]}
      {:function_call, [{:identifier, name} | arg_asts]}

  Pipe / transform encoding: `a|x|y` parses right-nested as
  `{:binary_op, [:|, a, {:binary_op, [:|, x, y]}]}`. The evaluator walks
  this chain left-to-right (apply `x` to `a`, then `y` to the result).
  `find_transforms/2` abstracts this encoding — it returns one match per
  transform with the reconstructed left-associative subject (e.g. for
  `a|x|y`, the subject of `y` is the AST of `a|x`).
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
    gather_transforms(ast, []) |> Enum.reverse()
  end

  def find_transforms(ast, name) when is_binary(name) do
    find_transforms(ast, [name])
  end

  def find_transforms(ast, names) when is_list(names) do
    ast
    |> find_transforms(:any)
    |> Enum.filter(fn %{name: n} -> n in names end)
  end

  # Recursive traversal that handles pipe chains specially to avoid double-counting.
  # When we encounter a pipe, we unpack the entire right-nested chain at once
  # and do NOT let the normal recursion descend into the chain's right side.
  defp gather_transforms({:binary_op, [:|, subject, right]}, acc) do
    # First recurse into the pipe's subject (non-chain child)
    acc = gather_transforms(subject, acc)
    # Unpack the full pipe chain starting from subject+right
    collect_pipe_chain(subject, right, acc)
  end

  defp gather_transforms({:array, elements}, acc) do
    Enum.reduce(elements, acc, &gather_transforms/2)
  end

  defp gather_transforms({:object, pairs}, acc) do
    Enum.reduce(pairs, acc, fn {:pair, [_k, v]}, a -> gather_transforms(v, a) end)
  end

  defp gather_transforms({:property_access, [obj, _prop]}, acc) do
    gather_transforms(obj, acc)
  end

  defp gather_transforms({:bracket_access, [obj, key]}, acc) do
    acc = gather_transforms(obj, acc)
    gather_transforms(key, acc)
  end

  defp gather_transforms({:ternary, [c, t, f]}, acc) do
    acc = gather_transforms(c, acc)
    acc = gather_transforms(t, acc)
    gather_transforms(f, acc)
  end

  defp gather_transforms({:binary_op, [_op, l, r]}, acc) do
    acc = gather_transforms(l, acc)
    gather_transforms(r, acc)
  end

  defp gather_transforms({:unary, [_op_tag, expr]}, acc) do
    gather_transforms(expr, acc)
  end

  defp gather_transforms({:function_call, [_head | args]}, acc) do
    Enum.reduce(args, acc, &gather_transforms/2)
  end

  defp gather_transforms(_leaf, acc), do: acc

  # Recursively unpacks right-nested pipes produced by the parser.
  # The parser encodes `a|x|y` as `{:binary_op, [:|, a, {binary_op, [:|, x, y]}]}`.
  # The evaluator treats the left of the inner pipe as the transform name and
  # recurses on the right. We mirror that here, tracking the reconstructed
  # left-associative pipe as the subject for each subsequent transform.
  defp collect_pipe_chain(subject, {:binary_op, [:|, transform_ast, rest]}, acc) do
    case extract_transform_call(transform_ast) do
      {:ok, name, args} ->
        new_subject = {:binary_op, [:|, subject, transform_ast]}
        acc = [%{name: name, subject: subject, args: args} | acc]
        acc = Enum.reduce(args, acc, &gather_transforms/2)
        collect_pipe_chain(new_subject, rest, acc)

      :error ->
        acc
    end
  end

  defp collect_pipe_chain(subject, transform_call, acc) do
    case extract_transform_call(transform_call) do
      {:ok, name, args} ->
        acc = [%{name: name, subject: subject, args: args} | acc]
        Enum.reduce(args, acc, &gather_transforms/2)

      :error ->
        acc
    end
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
