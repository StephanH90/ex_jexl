defmodule ExJexl.Evaluator do
  @moduledoc """
  JEXL expression evaluator that processes parsed AST.
  """

  alias ExJexl.Transforms

  @doc """
  Evaluates a parsed JEXL AST with the given context.
  """
  def eval(ast, context \\ %{})

  # Literals
  def eval({:integer, value}, _context), do: {:ok, value}
  def eval({:float, value}, _context), do: {:ok, value}
  def eval({:string, value}, _context), do: {:ok, value}
  def eval({:boolean, value}, _context), do: {:ok, value}
  def eval({:null, nil}, _context), do: {:ok, nil}

  # Identifiers - look up in context
  def eval({:identifier, name}, context) do
    case get_nested_value(context, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:ok, nil}
    end
  end

  # Arrays
  def eval({:array, elements}, context) do
    with {:ok, values} <- eval_list(elements, context) do
      {:ok, values}
    end
  end

  # Objects
  def eval({:object, pairs}, context) do
    eval_object_pairs(pairs, context, %{})
  end

  # Property access: obj.prop
  def eval({:property_access, [obj_ast, {:identifier, prop}]}, context) do
    with {:ok, obj} <- eval(obj_ast, context) do
      get_property(obj, prop)
    end
  end

  # Bracket access: obj[key]
  def eval({:bracket_access, [obj_ast, key_ast]}, context) do
    with {:ok, obj} <- eval(obj_ast, context),
         {:ok, key} <- eval(key_ast, context) do
      get_bracket_value(obj, key)
    end
  end

  # Binary operations
  def eval({:binary_op, [op, left_ast, right_ast]}, context) do
    case op do
      # Logical operators (short-circuit)
      :&& ->
        with {:ok, left} <- eval(left_ast, context) do
          if truthy?(left) do
            eval(right_ast, context)
          else
            {:ok, left}
          end
        end

      :|| ->
        with {:ok, left} <- eval(left_ast, context) do
          if truthy?(left) do
            {:ok, left}
          else
            eval(right_ast, context)
          end
        end

      # Pipe operator (transforms)
      :| ->
        with {:ok, left} <- eval(left_ast, context) do
          apply_transforms_chain(left, right_ast, context)
        end

      # Other binary operations
      _ ->
        with {:ok, left} <- eval(left_ast, context),
             {:ok, right} <- eval(right_ast, context) do
          case apply_binary_op(op, left, right) do
            {:ok, result} -> {:ok, result}
            {:error, _} = error -> error
          end
        end
    end
  end

  # Unary operations
  def eval({:unary, [{:op, :!}, expr_ast]}, context) do
    with {:ok, value} <- eval(expr_ast, context) do
      {:ok, !truthy?(value)}
    end
  end

  # Function calls
  def eval({:function_call, [{:identifier, name} | args_ast]}, context) do
    with {:ok, args} <- eval_list(args_ast, context) do
      call_function(name, args, context)
    end
  end

  # Fallback for unknown AST nodes
  def eval(ast, _context) do
    {:error, "Unknown AST node: #{inspect(ast)}"}
  end

  # Helper functions

  defp eval_list([], _context), do: {:ok, []}

  defp eval_list([head | tail], context) do
    with {:ok, head_value} <- eval(head, context),
         {:ok, tail_values} <- eval_list(tail, context) do
      {:ok, [head_value | tail_values]}
    end
  end

  defp eval_object_pairs([], _context, acc), do: {:ok, acc}

  defp eval_object_pairs([{:pair, [key_ast, value_ast]} | rest], context, acc) do
    with {:ok, key} <- get_object_key(key_ast),
         {:ok, value} <- eval(value_ast, context) do
      eval_object_pairs(rest, context, Map.put(acc, key, value))
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

  defp get_transform_name({:identifier, name}), do: {:ok, name}
  defp get_transform_name({:function_call, [{:identifier, name} | _]}), do: {:ok, name}
  defp get_transform_name(_), do: {:error, "Invalid transform"}

  # Handle chained transforms like items|reverse|first
  defp apply_transforms_chain(value, {:binary_op, [:| | [left_ast, right_ast]]}, context) do
    # For nested transforms, first apply the left transform, then apply the right
    with {:ok, transform_name} <- get_transform_name(left_ast),
         {:ok, intermediate} <- Transforms.apply_transform(transform_name, value, context) do
      apply_transforms_chain(intermediate, right_ast, context)
    end
  end

  defp apply_transforms_chain(value, transform_ast, context) do
    # Single transform
    with {:ok, transform_name} <- get_transform_name(transform_ast) do
      Transforms.apply_transform(transform_name, value, context)
    end
  end

  defp apply_binary_op(op, left, right) do
    case op do
      # Arithmetic
      :+ ->
        {:ok, add(left, right)}

      :- ->
        {:ok, subtract(left, right)}

      :* ->
        {:ok, multiply(left, right)}

      :/ ->
        case divide(left, right) do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
        end

      :% ->
        case modulo(left, right) do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
        end

      # Comparison
      :== ->
        {:ok, left == right}

      :!= ->
        {:ok, left != right}

      :> ->
        {:ok, compare(left, right) == :gt}

      :< ->
        {:ok, compare(left, right) == :lt}

      :>= ->
        {:ok, compare(left, right) in [:gt, :eq]}

      :<= ->
        {:ok, compare(left, right) in [:lt, :eq]}

      # Membership
      :in ->
        {:ok, member?(left, right)}

      _ ->
        {:error, "Unknown binary operator: #{op}"}
    end
  end

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
    cond do
      a == b -> :eq
      true -> :ne
    end
  end

  # Membership helpers
  defp member?(item, list) when is_list(list), do: item in list
  defp member?(key, map) when is_map(map), do: Map.has_key?(map, key)

  defp member?(substring, string) when is_binary(substring) and is_binary(string) do
    String.contains?(string, substring)
  end

  defp member?(_, _), do: false

  # Truthiness (JavaScript-like)
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(0), do: false
  defp truthy?(n) when is_float(n) and n == 0.0, do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(%{}) when map_size(%{}) == 0, do: false
  defp truthy?(_), do: true

  # Built-in function calls
  defp call_function("length", [value], _context) do
    case value do
      list when is_list(list) -> {:ok, length(list)}
      string when is_binary(string) -> {:ok, String.length(string)}
      map when is_map(map) -> {:ok, map_size(map)}
      _ -> {:ok, 0}
    end
  end

  defp call_function("keys", [map], _context) when is_map(map) do
    {:ok, Map.keys(map)}
  end

  defp call_function("values", [map], _context) when is_map(map) do
    {:ok, Map.values(map)}
  end

  defp call_function("type", [value], _context) do
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

  defp call_function(name, _args, _context) do
    {:error, "Unknown function: #{name}"}
  end
end
