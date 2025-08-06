defmodule ExJexl.Parser do
  @moduledoc """
  JEXL expression parser using NimbleParsec.
  """

  import NimbleParsec

  # Whitespace handling
  whitespace = ascii_char([?\s, ?\t, ?\n, ?\r]) |> repeat() |> ignore()

  # Basic tokens
  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({IO, :iodata_to_binary, []})
    |> unwrap_and_tag(:identifier)

  # Numbers (integers and floats)
  integer =
    optional(ascii_char([?-, ?+]))
    |> concat(ascii_char([?1..?9]))
    |> repeat(ascii_char([?0..?9]))
    |> reduce({IO, :iodata_to_binary, []})
    |> map({String, :to_integer, []})
    |> unwrap_and_tag(:integer)

  float =
    optional(ascii_char([?-, ?+]))
    |> repeat(ascii_char([?0..?9]))
    |> ascii_char([?.])
    |> times(ascii_char([?0..?9]), min: 1)
    |> reduce({IO, :iodata_to_binary, []})
    |> map({String, :to_float, []})
    |> unwrap_and_tag(:float)

  zero = ascii_char([?0]) |> replace(0) |> unwrap_and_tag(:integer)

  number = choice([float, integer, zero])

  # String literals
  string_literal =
    ignore(ascii_char([?"]))
    |> repeat_while(
      choice([
        ignore(ascii_char([?\\]))
        |> ascii_char([?", ?\\, ?n, ?r, ?t])
        |> map({__MODULE__, :unescape_char, []}),
        utf8_char(not: ?")
      ]),
      {:not_quote, []}
    )
    |> ignore(ascii_char([?"]))
    |> reduce({IO, :iodata_to_binary, []})
    |> unwrap_and_tag(:string)

  single_quoted_string =
    ignore(ascii_char([?']))
    |> repeat_while(
      choice([
        ignore(ascii_char([?\\]))
        |> ascii_char([?', ?\\, ?n, ?r, ?t])
        |> map({__MODULE__, :unescape_char, []}),
        utf8_char(not: ?')
      ]),
      {:not_single_quote, []}
    )
    |> ignore(ascii_char([?']))
    |> reduce({IO, :iodata_to_binary, []})
    |> unwrap_and_tag(:string)

  # Booleans
  boolean_true = string("true") |> replace(true) |> unwrap_and_tag(:boolean)
  boolean_false = string("false") |> replace(false) |> unwrap_and_tag(:boolean)
  boolean = choice([boolean_true, boolean_false])

  # Null
  null_literal = string("null") |> replace(nil) |> unwrap_and_tag(:null)

  # Basic literals
  literal = choice([boolean, null_literal, number, string_literal, single_quoted_string])

  # Operators
  # Arithmetic operators
  add_op = ascii_char([?+]) |> replace(:+) |> unwrap_and_tag(:op)
  sub_op = ascii_char([?-]) |> replace(:-) |> unwrap_and_tag(:op)
  mul_op = ascii_char([?*]) |> replace(:*) |> unwrap_and_tag(:op)
  div_op = ascii_char([?/]) |> replace(:/) |> unwrap_and_tag(:op)
  mod_op = ascii_char([?%]) |> replace(:%) |> unwrap_and_tag(:op)

  # Comparison operators
  eq_op = string("==") |> replace(:==) |> unwrap_and_tag(:op)
  ne_op = string("!=") |> replace(:!=) |> unwrap_and_tag(:op)
  ge_op = string(">=") |> replace(:>=) |> unwrap_and_tag(:op)
  le_op = string("<=") |> replace(:<=) |> unwrap_and_tag(:op)
  gt_op = ascii_char([?>]) |> replace(:>) |> unwrap_and_tag(:op)
  lt_op = ascii_char([?<]) |> replace(:<) |> unwrap_and_tag(:op)

  # Logical operators
  and_op = string("&&") |> replace(:&&) |> unwrap_and_tag(:op)
  or_op = string("||") |> replace(:||) |> unwrap_and_tag(:op)
  not_op = ascii_char([?!]) |> replace(:!) |> unwrap_and_tag(:op)

  # In operator - needs word boundaries to avoid matching parts of identifiers
  in_op = 
    string("in")
    |> lookahead(choice([whitespace, eos()]))
    |> replace(:in) 
    |> unwrap_and_tag(:op)

  # Property access
  dot = ascii_char([?.]) |> replace(:.) |> unwrap_and_tag(:op)

  # Pipe operator for transforms
  pipe_op = ascii_char([?|]) |> replace(:|) |> unwrap_and_tag(:op)

  # Parentheses and brackets
  lparen = ascii_char([?(]) |> ignore()
  rparen = ascii_char([?)]) |> ignore()
  lbracket = ascii_char([?[]) |> ignore()
  rbracket = ascii_char([?]]) |> ignore()
  lbrace = ascii_char([?{]) |> ignore()
  rbrace = ascii_char([?}]) |> ignore()
  comma = ascii_char([?,]) |> ignore()
  colon = ascii_char([?:]) |> ignore()

  # Forward declarations for recursive structures
  defparsec(:parse_expression, parsec(:expression))
  defparsec(:parse_primary, parsec(:primary))

  # Array literals
  array =
    lbracket
    |> optional(
      parsec(:expression)
      |> repeat(comma |> concat(whitespace) |> concat(parsec(:expression)))
    )
    |> concat(rbracket)
    |> tag(:array)

  # Object literals
  object_pair =
    choice([identifier, string_literal, single_quoted_string])
    |> ignore(whitespace)
    |> ignore(colon)
    |> ignore(whitespace)
    |> concat(parsec(:expression))
    |> tag(:pair)

  object =
    lbrace
    |> ignore(whitespace)
    |> optional(
      object_pair
      |> repeat(
        ignore(whitespace)
        |> ignore(comma)
        |> ignore(whitespace)
        |> concat(object_pair)
      )
    )
    |> ignore(whitespace)
    |> concat(rbrace)
    |> tag(:object)

  # Function calls
  function_call =
    identifier
    |> ignore(lparen)
    |> ignore(whitespace)
    |> optional(
      parsec(:expression)
      |> repeat(
        ignore(whitespace)
        |> ignore(comma)
        |> ignore(whitespace)
        |> concat(parsec(:expression))
      )
    )
    |> ignore(whitespace)
    |> ignore(rparen)
    |> tag(:function_call)

  # Property access with brackets
  bracket_access =
    lbracket
    |> concat(parsec(:expression))
    |> concat(rbracket)
    |> tag(:bracket_access)

  # Primary expressions (highest precedence)
  defcombinatorp(
    :primary,
    choice([
      ignore(lparen) |> concat(parsec(:expression)) |> ignore(rparen),
      function_call,
      array,
      object,
      literal,
      identifier
    ])
  )

  # Postfix expressions (property access, array access)
  postfix_op =
    choice([
      ignore(dot) |> concat(identifier) |> tag(:property_access),
      bracket_access
    ])

  defcombinatorp(
    :postfix,
    parsec(:primary)
    |> repeat(ignore(whitespace) |> concat(postfix_op))
    |> post_traverse({__MODULE__, :build_postfix, []})
  )

  # Unary expressions
  defcombinatorp(
    :unary,
    choice([
      not_op |> ignore(whitespace) |> concat(parsec(:unary)) |> tag(:unary),
      parsec(:postfix)
    ])
  )

  # Binary expressions with precedence
  defcombinatorp(
    :pipe,
    parsec(:unary)
    |> repeat(
      ignore(whitespace)
      |> concat(pipe_op)
      |> ignore(whitespace)
      |> concat(parsec(:unary))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :multiplicative,
    parsec(:pipe)
    |> repeat(
      ignore(whitespace)
      |> concat(choice([mul_op, div_op, mod_op]))
      |> ignore(whitespace)
      |> concat(parsec(:pipe))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :additive,
    parsec(:multiplicative)
    |> repeat(
      ignore(whitespace)
      |> concat(choice([add_op, sub_op]))
      |> ignore(whitespace)
      |> concat(parsec(:multiplicative))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :relational,
    parsec(:additive)
    |> repeat(
      ignore(whitespace)
      |> concat(choice([ge_op, le_op, gt_op, lt_op, in_op]))
      |> ignore(whitespace)
      |> concat(parsec(:additive))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :equality,
    parsec(:relational)
    |> repeat(
      ignore(whitespace)
      |> concat(choice([eq_op, ne_op]))
      |> ignore(whitespace)
      |> concat(parsec(:relational))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :logical_and,
    parsec(:equality)
    |> repeat(
      ignore(whitespace)
      |> concat(and_op)
      |> ignore(whitespace)
      |> concat(parsec(:equality))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  defcombinatorp(
    :logical_or,
    parsec(:logical_and)
    |> repeat(
      ignore(whitespace)
      |> concat(or_op)
      |> ignore(whitespace)
      |> concat(parsec(:logical_and))
    )
    |> post_traverse({__MODULE__, :build_binary_left, []})
  )

  # Main expression parser
  defcombinatorp(:expression, parsec(:logical_or))

  # Main parser entry point
  defparsec(
    :jexl_expression,
    ignore(whitespace)
    |> concat(parsec(:expression))
    |> ignore(whitespace)
    |> eos()
  )

  @doc """
  Parse a JEXL expression string into an AST.
  """
  def parse(expression) when is_binary(expression) do
    case jexl_expression(expression) do
      {:ok, [ast], "", _, _, _} -> {:ok, ast}
      {:ok, [_ast], rest, _, _, _} -> {:error, "Unexpected input: #{rest}"}
      {:error, reason, _rest, _context, _line, _offset} -> {:error, reason}
    end
  end

  # Helper functions for string unescaping
  def unescape_char(?"), do: ?"
  def unescape_char(?'), do: ?'
  def unescape_char(?\\), do: ?\\
  def unescape_char(?n), do: ?\n
  def unescape_char(?r), do: ?\r
  def unescape_char(?t), do: ?\t
  def unescape_char(char), do: char

  # Helper functions for quote checking
  def not_quote(<<?", _::binary>>, context, _, _), do: {:halt, context}
  def not_quote(_, context, _, _), do: {:cont, context}

  def not_single_quote(<<?', _::binary>>, context, _, _), do: {:halt, context}
  def not_single_quote(_, context, _, _), do: {:cont, context}

  # AST building helpers
  def build_postfix(rest, [base], context, _line, _offset) do
    {rest, [base], context}
  end

  def build_postfix(rest, [base | ops], context, _line, _offset) do
    # Handle the case where operands are reversed due to parser structure
    case {base, ops} do
      # Simple cases we already handle
      {{:property_access, [identifier: prop]}, [{:identifier, obj}]} ->
        result = {:property_access, [{:identifier, obj}, {:identifier, prop}]}
        {rest, [result], context}
      
      {{:bracket_access, [expr]}, [{:identifier, obj}]} ->
        result = {:bracket_access, [{:identifier, obj}, expr]}
        {rest, [result], context}
      
      {{:bracket_access, [expr]}, [obj_ast]} ->
        result = {:bracket_access, [obj_ast, expr]}
        {rest, [result], context}
        
      # Complex case: handle chains like data.users[0].name
      _ ->
        # ops contains the operations in reverse order
        all_parts = [base | ops]
        result = build_access_chain(all_parts)
        {rest, [result], context}
    end
  end

  # Build proper access chain from reversed parts
  defp build_access_chain(parts) do
    # Reverse and process
    parts
    |> Enum.reverse()
    |> build_chain_left_to_right()
  end

  defp build_chain_left_to_right([{:identifier, name}]), do: {:identifier, name}
  
  defp build_chain_left_to_right([{:identifier, name} | rest]) do
    base = {:identifier, name}
    apply_operations(base, rest)
  end
  
  defp build_chain_left_to_right([base | rest]) do
    apply_operations(base, rest)
  end

  defp apply_operations(acc, []), do: acc
  
  defp apply_operations(acc, [{:property_access, [identifier: prop]} | rest]) do
    new_acc = {:property_access, [acc, {:identifier, prop}]}
    apply_operations(new_acc, rest)
  end
  
  defp apply_operations(acc, [{:bracket_access, [expr]} | rest]) do
    new_acc = {:bracket_access, [acc, normalize_expr(expr)]}
    apply_operations(new_acc, rest)
  end
  
  defp apply_operations(acc, [_unknown | rest]) do
    apply_operations(acc, rest)
  end

  # Convert keyword list format to tuple format
  defp normalize_expr({:integer, val}), do: {:integer, val}
  defp normalize_expr({:identifier, name}), do: {:identifier, name}
  defp normalize_expr(integer: val), do: {:integer, val}
  defp normalize_expr(identifier: name), do: {:identifier, name}
  defp normalize_expr(other), do: other

  def build_binary_left(rest, [left], context, _line, _offset) do
    {rest, [left], context}
  end

  def build_binary_left(rest, [left | remaining], context, _line, _offset) do
    result =
      remaining
      |> Enum.chunk_every(2)
      |> Enum.reduce(left, fn [op, right], acc ->
        case op do
          {:op, op_name} -> {:binary_op, [op_name, right, acc]}
          _ -> acc
        end
      end)

    {rest, [result], context}
  end
end
