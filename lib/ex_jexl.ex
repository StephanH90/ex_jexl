defmodule ExJexl do
  @moduledoc """
  A JEXL (JavaScript Expression Language) evaluator for Elixir using NimbleParsec.

  JEXL is a simple expression language designed for evaluating expressions
  in a safe, sandboxed environment.
  """

  alias ExJexl.Parser
  alias ExJexl.Evaluator

  @doc """
  Evaluates a JEXL expression with the given context.

  ## Examples

      iex> ExJexl.eval("name", %{"name" => "Alice"})
      {:ok, "Alice"}
      
      iex> ExJexl.eval("age > 18", %{"age" => 25})
      {:ok, true}
      
      iex> ExJexl.eval("items|length", %{"items" => [1, 2, 3]})
      {:ok, 3}
  """
  def eval(expression, context \\ %{}) when is_binary(expression) do
    with {:ok, ast} <- Parser.parse(expression),
         {:ok, result} <- Evaluator.eval(ast, context) do
      {:ok, result}
    end
  end

  @doc """
  Evaluates a JEXL expression with the given context, raising on error.

  ## Examples

      iex> ExJexl.eval!("name", %{"name" => "Alice"})
      "Alice"
  """
  def eval!(expression, context \\ %{}) do
    case eval(expression, context) do
      {:ok, result} -> result
      {:error, reason} -> raise "JEXL evaluation error: #{inspect(reason)}"
    end
  end
end
