defmodule ExJexl.Transforms do
  @moduledoc """
  JEXL transforms (filters) for data manipulation.
  """

  import ExJexl.Helpers, only: [truthy?: 1]
  require Logger

  @doc """
  Apply a built-in transform to a value.
  """
  @spec apply_transform(String.t(), term(), list()) :: {:ok, term()} | {:error, String.t()}
  def apply_transform(name, value, args \\ [])

  # Array transforms
  def apply_transform("length", value, _args) do
    case value do
      list when is_list(list) -> {:ok, length(list)}
      string when is_binary(string) -> {:ok, String.length(string)}
      map when is_map(map) -> {:ok, map_size(map)}
      _ -> {:ok, nil}
    end
  end

  def apply_transform("first", list, _args) when is_list(list) do
    case list do
      [] -> {:ok, nil}
      [first | _] -> {:ok, first}
    end
  end

  def apply_transform("first", _value, _args), do: {:ok, nil}

  def apply_transform("last", list, _args) when is_list(list) do
    case list do
      [] -> {:ok, nil}
      _ -> {:ok, List.last(list)}
    end
  end

  def apply_transform("last", _value, _args), do: {:ok, nil}

  def apply_transform("reverse", list, _args) when is_list(list) do
    {:ok, Enum.reverse(list)}
  end

  def apply_transform("sort", list, _args) when is_list(list) do
    {:ok, Enum.sort(list)}
  end

  def apply_transform("unique", list, _args) when is_list(list) do
    {:ok, Enum.uniq(list)}
  end

  def apply_transform("flatten", list, _args) when is_list(list) do
    {:ok, List.flatten(list)}
  end

  def apply_transform("join", list, _args) when is_list(list) do
    strings = Enum.map(list, &to_string/1)
    {:ok, Enum.join(strings, ",")}
  end

  # String transforms
  def apply_transform("upper", string, _args) when is_binary(string) do
    {:ok, String.upcase(string)}
  end

  def apply_transform("lower", string, _args) when is_binary(string) do
    {:ok, String.downcase(string)}
  end

  def apply_transform("trim", string, _args) when is_binary(string) do
    {:ok, String.trim(string)}
  end

  def apply_transform("split", string, _args) when is_binary(string) do
    {:ok, String.split(string, ",")}
  end

  # Object transforms
  def apply_transform("keys", map, _args) when is_map(map) do
    {:ok, Map.keys(map)}
  end

  def apply_transform("values", map, _args) when is_map(map) do
    {:ok, Map.values(map)}
  end

  # Numeric transforms
  def apply_transform("abs", number, _args) when is_number(number) do
    safe(fn -> abs(number) end)
  end

  def apply_transform("abs", _value, _args), do: {:ok, nil}

  def apply_transform("round", n, args) when is_number(n) do
    ndigits =
      case args do
        [] -> 0
        [d] when is_integer(d) -> d
        _ -> 0
      end

    safe(fn ->
      power = :math.pow(10, ndigits)
      :math.floor(n * power + 0.5) / power
    end)
  end

  def apply_transform("round", _value, _args), do: {:ok, nil}

  def apply_transform("floor", n, _args) when is_number(n) do
    safe(fn -> trunc(:math.floor(n * 1.0)) end)
  end

  def apply_transform("floor", _value, _args), do: {:ok, nil}

  def apply_transform("ceil", n, _args) when is_number(n) do
    safe(fn -> trunc(:math.ceil(n * 1.0)) end)
  end

  def apply_transform("ceil", _value, _args), do: {:ok, nil}

  # Type checking transforms
  def apply_transform("type", value, _args) do
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

  # Boolean transforms
  def apply_transform("not", value, _args) do
    {:ok, !truthy?(value)}
  end

  def apply_transform("mapby", arr, [key]) when is_list(arr) do
    {:ok, Enum.map(arr, &mapby_value(&1, key))}
  end

  def apply_transform("mapby", arr, keys) when is_list(arr) and is_list(keys) and length(keys) > 1 do
    result = Enum.map(arr, fn obj ->
      Enum.map(keys, &mapby_value(obj, &1))
    end)
    {:ok, result}
  end

  def apply_transform("mapby", _value, _args), do: {:ok, nil}

  def apply_transform("stringify", value, _args) do
    encoder = fn
      nil, _enc -> "null"
      other, enc -> :json.encode_value(other, enc)
    end

    try do
      {:ok, IO.iodata_to_binary(:json.encode(value, encoder))}
    rescue
      ErlangError -> {:ok, nil}
      Protocol.UndefinedError -> {:ok, nil}
    end
  end

  def apply_transform("min", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> safe(fn -> Enum.min(nums) end)
    end
  end

  def apply_transform("max", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> safe(fn -> Enum.max(nums) end)
    end
  end

  def apply_transform("sum", value, _args) do
    safe(fn -> Enum.sum(filter_numbers(value)) end)
  end

  def apply_transform("avg", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> safe(fn -> Enum.sum(nums) / length(nums) end)
    end
  end

  def apply_transform("debug", value, []) do
    Logger.info("[JEXL debug] value = #{inspect(value)}")
    {:ok, value}
  end

  def apply_transform("debug", value, [label]) do
    Logger.info("[JEXL debug] #{label}: #{inspect(value)}")
    {:ok, value}
  end

  # Default case
  def apply_transform(name, _value, _args) do
    {:error, "Unknown transform: #{name}"}
  end

  defp mapby_value(obj, key) when is_map(obj) do
    case Map.fetch(obj, key) do
      {:ok, v} -> v
      :error -> Map.get(obj, to_string(key))
    end
  end

  defp mapby_value(_obj, _key), do: nil

  defp filter_numbers(arr) when is_list(arr) do
    Enum.filter(arr, &valid_number?/1)
  end

  defp filter_numbers(_), do: []

  defp valid_number?(x) when is_integer(x), do: true
  defp valid_number?(x) when is_float(x), do: x == x
  defp valid_number?(_), do: false

  defp safe(fun) do
    try do
      {:ok, fun.()}
    rescue
      ArithmeticError -> {:ok, nil}
      ArgumentError -> {:ok, nil}
      FunctionClauseError -> {:ok, nil}
    end
  end
end
