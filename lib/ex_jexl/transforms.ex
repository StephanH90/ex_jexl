defmodule ExJexl.Transforms do
  @moduledoc """
  JEXL transforms (filters) for data manipulation.
  """

  @doc """
  Apply a transform to a value with the given context.
  """
  def apply_transform(name, value, _context \\ %{})

  # Array transforms
  def apply_transform("length", value, _context) do
    case value do
      list when is_list(list) -> {:ok, length(list)}
      string when is_binary(string) -> {:ok, String.length(string)}
      map when is_map(map) -> {:ok, map_size(map)}
      _ -> {:ok, 0}
    end
  end

  def apply_transform("first", list, _context) when is_list(list) do
    case list do
      [] -> {:ok, nil}
      [first | _] -> {:ok, first}
    end
  end

  def apply_transform("last", list, _context) when is_list(list) do
    case list do
      [] -> {:ok, nil}
      _ -> {:ok, List.last(list)}
    end
  end

  def apply_transform("reverse", list, _context) when is_list(list) do
    {:ok, Enum.reverse(list)}
  end

  def apply_transform("sort", list, _context) when is_list(list) do
    {:ok, Enum.sort(list)}
  end

  def apply_transform("unique", list, _context) when is_list(list) do
    {:ok, Enum.uniq(list)}
  end

  def apply_transform("flatten", list, _context) when is_list(list) do
    {:ok, List.flatten(list)}
  end

  def apply_transform("join", list, _context) when is_list(list) do
    strings = Enum.map(list, &to_string/1)
    {:ok, Enum.join(strings, ",")}
  end

  # String transforms
  def apply_transform("upper", string, _context) when is_binary(string) do
    {:ok, String.upcase(string)}
  end

  def apply_transform("lower", string, _context) when is_binary(string) do
    {:ok, String.downcase(string)}
  end

  def apply_transform("trim", string, _context) when is_binary(string) do
    {:ok, String.trim(string)}
  end

  def apply_transform("split", string, _context) when is_binary(string) do
    {:ok, String.split(string, ",")}
  end

  # Object transforms
  def apply_transform("keys", map, _context) when is_map(map) do
    {:ok, Map.keys(map)}
  end

  def apply_transform("values", map, _context) when is_map(map) do
    {:ok, Map.values(map)}
  end

  # Numeric transforms
  def apply_transform("abs", number, _context) when is_number(number) do
    {:ok, abs(number)}
  end

  def apply_transform("round", number, _context) when is_number(number) do
    {:ok, round(number)}
  end

  def apply_transform("floor", number, _context) when is_number(number) do
    {:ok, trunc(number)}
  end

  def apply_transform("ceil", number, _context) when is_number(number) do
    {:ok, trunc(number) + if(number == trunc(number), do: 0, else: 1)}
  end

  # Type checking transforms
  def apply_transform("type", value, _context) do
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
  def apply_transform("not", value, _context) do
    {:ok, !truthy?(value)}
  end

  # Default case
  def apply_transform(name, _value, _context) do
    {:error, "Unknown transform: #{name}"}
  end

  # Helper function for truthiness
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(0), do: false
  defp truthy?(n) when is_float(n) and n == 0.0, do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(%{}) when map_size(%{}) == 0, do: false
  defp truthy?(_), do: true
end
