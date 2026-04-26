defmodule ExJexl do
  @moduledoc """
  A JEXL (JavaScript Expression Language) evaluator for Elixir using NimbleParsec.

  JEXL is a simple expression language designed for evaluating expressions
  in a safe, sandboxed environment.
  """

  alias ExJexl.Evaluator
  alias ExJexl.Parser

  defmacro __using__(opts) do
    transforms = Keyword.get(opts, :transforms, Macro.escape(%{}))
    functions = Keyword.get(opts, :functions, Macro.escape(%{}))
    validators = Keyword.get(opts, :validators, [])

    quote do
      defp __default_transforms__, do: unquote(transforms)
      defp __default_functions__, do: unquote(functions)
      defp __default_validators__, do: unquote(validators)

      def eval(expression, context \\ %{}, opts \\ []) do
        merged_opts = [
          transforms: Map.merge(__default_transforms__(), opts[:transforms] || %{}),
          functions: Map.merge(__default_functions__(), opts[:functions] || %{})
        ]

        ExJexl.eval(expression, context, merged_opts)
      end

      def eval!(expression, context \\ %{}, opts \\ []) do
        merged_opts = [
          transforms: Map.merge(__default_transforms__(), opts[:transforms] || %{}),
          functions: Map.merge(__default_functions__(), opts[:functions] || %{})
        ]

        ExJexl.eval!(expression, context, merged_opts)
      end

      def validate(expression, opts \\ []) do
        extra = opts[:validators] || []
        ExJexl.Validator.validate(expression, __default_validators__() ++ extra)
      end
    end
  end

  @doc """
  Evaluates a JEXL expression with the given context.

  ## Options

    * `:functions` - a map of custom function names to functions that receive
      a list of arguments
    * `:transforms` - a map of custom transform names to functions that receive
      the piped value

  ## Examples

      iex> ExJexl.eval("name", %{"name" => "Alice"})
      {:ok, "Alice"}

      iex> ExJexl.eval("age > 18", %{"age" => 25})
      {:ok, true}

      iex> ExJexl.eval("items|length", %{"items" => [1, 2, 3]})
      {:ok, 3}
  """
  @spec eval(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def eval(expression, context \\ %{}, opts \\ []) when is_binary(expression) do
    env = build_env(context, opts)

    with {:ok, ast} <- Parser.parse(expression) do
      Evaluator.eval(ast, env)
    end
  end

  @doc """
  Evaluates a JEXL expression with the given context, raising on error.

  Accepts the same options as `eval/3`.

  ## Examples

      iex> ExJexl.eval!("name", %{"name" => "Alice"})
      "Alice"
  """
  @spec eval!(String.t(), map(), keyword()) :: term()
  def eval!(expression, context \\ %{}, opts \\ []) do
    case eval(expression, context, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "JEXL evaluation error: #{inspect(reason)}"
    end
  end

  defp build_env(context, opts) do
    %{
      context: context,
      functions: opts[:functions] || %{},
      transforms: opts[:transforms] || %{}
    }
  end
end
