defmodule ExJexl.Evaluator do
  @moduledoc """
  JEXL expression evaluator that processes parsed AST.
  """

  alias ExJexl.Helpers
  alias ExJexl.Transforms

  @type env :: %{
          context: map(),
          functions: %{optional(String.t()) => (list() -> term())},
          transforms: %{optional(String.t()) => (term() -> term()) | (term(), map() -> term())}
        }

  @doc """
  Evaluates a parsed JEXL AST with the given environment.

  The env map contains `:context`, `:functions`, and `:transforms`.
  """
  @spec eval(term(), env()) :: {:ok, term()} | {:error, term()}
  def eval(ast, env \\ %{context: %{}, functions: %{}, transforms: %{}})

  # Literals
  def eval({:integer, value}, _env), do: {:ok, value}
  def eval({:float, value}, _env), do: {:ok, value}
  def eval({:string, value}, _env), do: {:ok, value}
  def eval({:boolean, value}, _env), do: {:ok, value}
  def eval({:null, nil}, _env), do: {:ok, nil}

  # Identifiers - look up in context
  def eval({:identifier, name}, env) do
    case get_nested_value(env.context, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:ok, nil}
    end
  end

  # Arrays
  def eval({:array, elements}, env) do
    eval_list(elements, env)
  end

  # Objects
  def eval({:object, pairs}, env) do
    eval_object_pairs(pairs, env, %{})
  end

  # Property access: obj.prop
  def eval({:property_access, [obj_ast, {:identifier, prop}]}, env) do
    with {:ok, obj} <- eval(obj_ast, env) do
      get_property(obj, prop)
    end
  end

  # Bracket access: obj[key]
  def eval({:bracket_access, [obj_ast, key_ast]}, env) do
    with {:ok, obj} <- eval(obj_ast, env),
         {:ok, key} <- eval(key_ast, env) do
      get_bracket_value(obj, key)
    end
  end

  # Ternary expression
  def eval({:ternary, [condition, true_expr, false_expr]}, env) do
    with {:ok, cond_val} <- eval(condition, env) do
      if Helpers.truthy?(cond_val) do
        eval(true_expr, env)
      else
        eval(false_expr, env)
      end
    end
  end

  # Binary operations - logical (short-circuit)
  def eval({:binary_op, [:&&, left_ast, right_ast]}, env) do
    with {:ok, left} <- eval(left_ast, env) do
      if Helpers.truthy?(left), do: eval(right_ast, env), else: {:ok, left}
    end
  end

  def eval({:binary_op, [:||, left_ast, right_ast]}, env) do
    with {:ok, left} <- eval(left_ast, env) do
      if Helpers.truthy?(left), do: {:ok, left}, else: eval(right_ast, env)
    end
  end

  # Pipe operator (transforms)
  def eval({:binary_op, [:|, left_ast, right_ast]}, env) do
    with {:ok, left} <- eval(left_ast, env) do
      apply_transforms_chain(left, right_ast, env)
    end
  end

  # Other binary operations
  def eval({:binary_op, [op, left_ast, right_ast]}, env) do
    with {:ok, left} <- eval(left_ast, env),
         {:ok, right} <- eval(right_ast, env) do
      apply_binary_op(op, left, right)
    end
  end

  # Unary operations
  def eval({:unary, [{:op, :!}, expr_ast]}, env) do
    with {:ok, value} <- eval(expr_ast, env) do
      {:ok, !Helpers.truthy?(value)}
    end
  end

  # Function calls
  def eval({:function_call, [{:identifier, name} | args_ast]}, env) do
    with {:ok, args} <- eval_list(args_ast, env) do
      call_function(name, args, env)
    end
  end

  # Fallback for unknown AST nodes
  def eval(ast, _env) do
    {:error, "Unknown AST node: #{inspect(ast)}"}
  end

  # Helper functions

  defp eval_list([], _env), do: {:ok, []}

  defp eval_list([head | tail], env) do
    with {:ok, head_value} <- eval(head, env),
         {:ok, tail_values} <- eval_list(tail, env) do
      {:ok, [head_value | tail_values]}
    end
  end

  defp eval_object_pairs([], _env, acc), do: {:ok, acc}

  defp eval_object_pairs([{:pair, [key_ast, value_ast]} | rest], env, acc) do
    with {:ok, key} <- get_object_key(key_ast),
         {:ok, value} <- eval(value_ast, env) do
      eval_object_pairs(rest, env, Map.put(acc, key, value))
    end
  end

  defp get_object_key({:identifier, name}), do: {:ok, name}
  defp get_object_key({:string, value}), do: {:ok, value}
  defp get_object_key(_), do: {:error, "Invalid object key"}

  defp get_nested_value(context, key) when is_map(context) do
    case Map.get(context, key) do
      nil ->
        # Try atom key if string key fails, and vice versa
        alt_key = if is_atom(key), do: Atom.to_string(key), else: String.to_existing_atom(key)

        case Map.get(context, alt_key) do
          nil -> :error
          value -> {:ok, value}
        end

      value ->
        {:ok, value}
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom/1 raises if the atom doesn't exist
      :error
  end

  defp get_nested_value(_, _), do: :error

  defp get_property(obj, prop) when is_map(obj) do
    case Map.get(obj, prop) do
      nil ->
        case Map.get(obj, to_string(prop)) do
          nil -> {:ok, nil}
          value -> {:ok, value}
        end

      value ->
        {:ok, value}
    end
  end

  defp get_property(_, _), do: {:ok, nil}

  defp get_bracket_value(obj, key) when is_map(obj) do
    case Map.get(obj, key) do
      nil -> {:ok, nil}
      value -> {:ok, value}
    end
  end

  defp get_bracket_value(list, index) when is_list(list) and is_integer(index) do
    case Enum.at(list, index) do
      nil -> {:ok, nil}
      value -> {:ok, value}
    end
  end

  defp get_bracket_value(_, _), do: {:ok, nil}

  defp get_transform_info({:identifier, name}), do: {:ok, name, []}
  defp get_transform_info({:function_call, [{:identifier, name} | args]}), do: {:ok, name, args}
  defp get_transform_info(_), do: {:error, "Invalid transform"}

  # Handle chained transforms like items|reverse|first
  defp apply_transforms_chain(value, {:binary_op, [:| | [left_ast, right_ast]]}, env) do
    with {:ok, name, arg_asts} <- get_transform_info(left_ast),
         {:ok, args} <- eval_list(arg_asts, env),
         {:ok, intermediate} <- apply_transform(name, value, args, env) do
      apply_transforms_chain(intermediate, right_ast, env)
    end
  end

  defp apply_transforms_chain(value, transform_ast, env) do
    with {:ok, name, arg_asts} <- get_transform_info(transform_ast),
         {:ok, args} <- eval_list(arg_asts, env) do
      apply_transform(name, value, args, env)
    end
  end

  defp apply_transform(name, value, args, env) do
    custom_transforms = env[:transforms] || %{}

    case Map.get(custom_transforms, name) do
      nil -> Transforms.apply_transform(name, value, args)
      func when is_function(func, 3) -> {:ok, func.(value, args, env.context)}
      func when is_function(func, 2) -> {:ok, func.(value, env.context)}
      func when is_function(func, 1) -> {:ok, func.(value)}
    end
  end

  defp apply_binary_op(:+, left, right), do: {:ok, add(left, right)}
  defp apply_binary_op(:-, left, right), do: {:ok, subtract(left, right)}
  defp apply_binary_op(:*, left, right), do: {:ok, multiply(left, right)}
  defp apply_binary_op(:/, left, right), do: divide(left, right)
  defp apply_binary_op(:%, left, right), do: modulo(left, right)
  defp apply_binary_op(:==, left, right), do: {:ok, left == right}
  defp apply_binary_op(:!=, left, right), do: {:ok, left != right}
  defp apply_binary_op(:>, left, right), do: {:ok, compare(left, right) == :gt}
  defp apply_binary_op(:<, left, right), do: {:ok, compare(left, right) == :lt}
  defp apply_binary_op(:>=, left, right), do: {:ok, compare(left, right) in [:gt, :eq]}
  defp apply_binary_op(:<=, left, right), do: {:ok, compare(left, right) in [:lt, :eq]}
  defp apply_binary_op(:in, left, right), do: {:ok, member?(left, right)}
  defp apply_binary_op(op, _, _), do: {:error, "Unknown binary operator: #{op}"}

  # Arithmetic helpers
  defp add(a, b) when is_number(a) and is_number(b), do: a + b
  defp add(a, b) when is_binary(a) and is_binary(b), do: a <> b
  defp add(a, b) when is_list(a) and is_list(b), do: a ++ b
  defp add(_, _), do: nil

  defp subtract(a, b) when is_number(a) and is_number(b), do: a - b
  defp subtract(_, _), do: nil

  defp multiply(a, b) when is_number(a) and is_number(b), do: a * b
  defp multiply(_, _), do: nil

  defp divide(_a, 0), do: {:error, "Division by zero"}
  defp divide(_a, b) when is_float(b) and b == 0.0, do: {:error, "Division by zero"}
  defp divide(a, b) when is_number(a) and is_number(b), do: {:ok, a / b}
  defp divide(_, _), do: {:error, "Invalid division operands"}

  defp modulo(_a, 0), do: {:error, "Modulo by zero"}
  defp modulo(_a, b) when is_float(b) and b == 0.0, do: {:error, "Modulo by zero"}
  defp modulo(a, b) when is_integer(a) and is_integer(b), do: {:ok, rem(a, b)}
  defp modulo(_, _), do: {:error, "Invalid modulo operands"}

  # Comparison helpers
  defp compare(a, b) when is_number(a) and is_number(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  defp compare(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  defp compare(a, b) do
    if a == b, do: :eq, else: :ne
  end

  # Membership helpers
  defp member?(item, list) when is_list(list), do: item in list
  defp member?(key, map) when is_map(map), do: Map.has_key?(map, key)

  defp member?(substring, string) when is_binary(substring) and is_binary(string) do
    String.contains?(string, substring)
  end

  defp member?(_, _), do: false

  # Built-in function calls
  defp call_function(name, args, env) do
    custom_functions = env[:functions] || %{}

    case Map.get(custom_functions, name) do
      nil -> builtin_function(name, args)
      func when is_function(func, 1) -> {:ok, func.(args)}
    end
  end

  defp builtin_function("length", [value]) do
    case value do
      list when is_list(list) -> {:ok, length(list)}
      string when is_binary(string) -> {:ok, String.length(string)}
      map when is_map(map) -> {:ok, map_size(map)}
      _ -> {:ok, 0}
    end
  end

  defp builtin_function("keys", [map]) when is_map(map) do
    {:ok, Map.keys(map)}
  end

  defp builtin_function("values", [map]) when is_map(map) do
    {:ok, Map.values(map)}
  end

  defp builtin_function("type", [value]) do
    type =
      cond do
        is_nil(value) -> "null"
        is_boolean(value) -> "boolean"
        is_integer(value) -> "number"
        is_float(value) -> "number"
        is_binary(value) -> "string"
        is_list(value) -> "array"
        is_map(value) -> "object"
        true -> "unknown"
      end

    {:ok, type}
  end

  defp builtin_function(name, _args) do
    {:error, "Unknown function: #{name}"}
  end
end
