defmodule ExJexl.Helpers do
  @moduledoc """
  Shared helper functions for ExJexl modules.
  """

  @doc """
  Checks if a value is truthy (JavaScript-like semantics).

  Returns `false` for `nil`, `false`, `0`, `0.0`, `""`, `[]`, and empty maps.
  Returns `true` for everything else.
  """
  @spec truthy?(term()) :: boolean()
  def truthy?(nil), do: false
  def truthy?(false), do: false
  def truthy?(0), do: false
  def truthy?(n) when is_float(n) and n == 0.0, do: false
  def truthy?(""), do: false
  def truthy?([]), do: false
  def truthy?(%{} = map) when map_size(map) == 0, do: false
  def truthy?(_), do: true
end
