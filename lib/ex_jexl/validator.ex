defmodule ExJexl.Validator do
  @moduledoc """
  Pluggable validation API for JEXL expressions.

  ex_jexl ships zero domain validators by default. Host applications register
  their own validators and pass them to `validate/2` (or via
  `use ExJexl, validators: [...]`).

  Each validator is a function `(ast -> [String.t()])` that returns a list of
  error messages. All validators run independently and their errors are merged
  into a single list — no fail-fast.

  ## Example

      validator = fn ast ->
        ast
        |> ExJexl.AST.find_transforms("answer")
        |> Enum.reject(fn %{subject: subject} -> match?({:string, _}, subject) end)
        |> Enum.map(fn _ -> "answer subject must be a string slug" end)
      end

      ExJexl.Validator.validate("'q'|answer", [validator])
      # => {:ok, []}

      ExJexl.Validator.validate("x|answer", [validator])
      # => {:ok, ["answer subject must be a string slug"]}
  """

  alias ExJexl.Parser

  @type ast :: tuple()
  @type validator :: (ast -> [String.t()])
  @type result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Parse and validate an expression.

  Returns `{:ok, errors}` where `errors` is a (possibly empty) list of error
  messages from running each validator over the parsed AST. Returns
  `{:error, parse_error}` if the expression itself is unparseable; in this
  case validators are not run.
  """
  @spec validate(String.t(), [validator]) :: result
  def validate(expression, validators \\ []) when is_binary(expression) do
    with {:ok, ast} <- Parser.parse(expression) do
      {:ok, validate_ast(ast, validators)}
    end
  end

  @doc """
  Run validators against an already-parsed AST.

  Returns a list of error messages collected from all validators in order.
  """
  @spec validate_ast(ast, [validator]) :: [String.t()]
  def validate_ast(ast, validators \\ []) do
    Enum.flat_map(validators, fn v -> v.(ast) end)
  end
end
