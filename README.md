# ExJexl

## Disclaimer

This code has been pretty much one shotted by Claude. I haven't tested it in a production setting. It might be full of security issues. **USE AT YOUR OWN RISK!**

[![Hex.pm](https://img.shields.io/hexpm/v/ex_jexl.svg)](https://hex.pm/packages/ex_jexl)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_jexl)

A JEXL (JavaScript Expression Language) evaluator for Elixir, built with NimbleParsec.

## Installation

Add `ex_jexl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_jexl, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Simple arithmetic
ExJexl.eval("2 + 3 * 4")
# => {:ok, 14}

# Working with context
context = %{
  "user" => %{"name" => "Alice", "age" => 30},
  "items" => [1, 2, 3, 4, 5]
}

ExJexl.eval("user.name", context)
# => {:ok, "Alice"}

ExJexl.eval("user.age >= 18", context)
# => {:ok, true}

ExJexl.eval("items|length", context)
# => {:ok, 5}
```

## Language Reference

### Literals

```elixir
ExJexl.eval("42")           # => {:ok, 42}
ExJexl.eval("3.14")         # => {:ok, 3.14}
ExJexl.eval("\"hello\"")    # => {:ok, "hello"}
ExJexl.eval("true")         # => {:ok, true}
ExJexl.eval("null")         # => {:ok, nil}
ExJexl.eval("[1, 2, 3]")    # => {:ok, [1, 2, 3]}
ExJexl.eval("{\"key\": \"value\"}")  # => {:ok, %{"key" => "value"}}
```

### Arithmetic Operations

```elixir
ExJexl.eval("10 + 5")       # => {:ok, 15}
ExJexl.eval("10 - 3")       # => {:ok, 7}
ExJexl.eval("4 * 5")        # => {:ok, 20}
ExJexl.eval("15 / 3")       # => {:ok, 5.0}
ExJexl.eval("17 % 5")       # => {:ok, 2}
ExJexl.eval("2 + 3 * 4")    # => {:ok, 14} (respects precedence)
ExJexl.eval("(2 + 3) * 4")  # => {:ok, 20}
```

### Comparison and Logical Operations

```elixir
ExJexl.eval("5 == 5")         # => {:ok, true}
ExJexl.eval("5 != 3")         # => {:ok, true}
ExJexl.eval("10 > 5")         # => {:ok, true}
ExJexl.eval("true && false")  # => {:ok, false}
ExJexl.eval("true || false")  # => {:ok, true}
ExJexl.eval("!true")          # => {:ok, false}
```

### Property Access

```elixir
context = %{
  "user" => %{"name" => "Alice"},
  "items" => [10, 20, 30],
  "key" => "name"
}

ExJexl.eval("user.name", context)       # => {:ok, "Alice"}
ExJexl.eval("user[\"name\"]", context)  # => {:ok, "Alice"}
ExJexl.eval("user[key]", context)       # => {:ok, "Alice"}
ExJexl.eval("items[0]", context)        # => {:ok, 10}
```

Both string and atom keys are supported in contexts.

### Membership Testing

```elixir
ExJexl.eval("3 in numbers", %{"numbers" => [1, 2, 3]})        # => {:ok, true}
ExJexl.eval("\"name\" in user", %{"user" => %{"name" => "Alice"}})  # => {:ok, true}
ExJexl.eval("\"world\" in text", %{"text" => "hello world"})  # => {:ok, true}
```

### Ternary Expressions

```elixir
ExJexl.eval("age >= 18 ? 'adult' : 'minor'", %{"age" => 25})
# => {:ok, "adult"}
```

### Built-in Transforms

Transforms use a pipe syntax and can be chained:

```elixir
context = %{"numbers" => [3, 1, 4, 1, 5], "text" => "Hello World"}

ExJexl.eval("numbers|length", context)        # => {:ok, 5}
ExJexl.eval("numbers|first", context)         # => {:ok, 3}
ExJexl.eval("numbers|last", context)          # => {:ok, 5}
ExJexl.eval("numbers|reverse", context)       # => {:ok, [5, 1, 4, 1, 3]}
ExJexl.eval("numbers|sort", context)          # => {:ok, [1, 1, 3, 4, 5]}
ExJexl.eval("numbers|unique", context)        # => {:ok, [3, 1, 4, 5]}
ExJexl.eval("text|upper", context)            # => {:ok, "HELLO WORLD"}
ExJexl.eval("text|lower", context)            # => {:ok, "hello world"}
ExJexl.eval("numbers|reverse|first", context) # => {:ok, 5}
```

Available built-in transforms: `length`, `first`, `last`, `reverse`, `sort`, `unique`, `flatten`, `join`, `upper`, `lower`, `trim`, `split`, `keys`, `values`, `type`.

### Built-in Functions

```elixir
ExJexl.eval("length(items)", %{"items" => [1, 2, 3]})  # => {:ok, 3}
ExJexl.eval("keys(user)", %{"user" => %{"a" => 1}})    # => {:ok, ["a"]}
ExJexl.eval("values(user)", %{"user" => %{"a" => 1}})  # => {:ok, [1]}
ExJexl.eval("type(42)")                                  # => {:ok, "number"}
```

## Custom Transforms and Functions

### Per-call

Pass custom transforms and functions via opts:

```elixir
# Custom function
ExJexl.eval("add(1, 2)", %{}, functions: %{"add" => fn [a, b] -> a + b end})
# => {:ok, 3}

# Custom transform (arity 1 - receives the piped value)
ExJexl.eval("value|double", %{"value" => 5}, transforms: %{"double" => fn val -> val * 2 end})
# => {:ok, 10}

# Custom transform (arity 2 - receives the piped value and the context)
ExJexl.eval(
  "name|greet",
  %{"name" => "Alice", "greeting" => "Hello"},
  transforms: %{"greet" => fn val, ctx -> "#{ctx["greeting"]} #{val}" end}
)
# => {:ok, "Hello Alice"}
```

Custom transforms and functions override built-ins with the same name.

### Application-level with `use ExJexl`

For transforms and functions you want available across your application without passing opts every time, define a wrapper module:

```elixir
defmodule MyApp.Jexl do
  use ExJexl,
    transforms: %{
      "double" => fn val -> val * 2 end,
      "upcase" => &String.upcase/1,
      "with_prefix" => fn val, ctx -> "#{ctx["prefix"]} #{val}" end
    },
    functions: %{
      "add" => fn [a, b] -> a + b end
    }
end
```

Then use it like `ExJexl` but with your defaults baked in:

```elixir
MyApp.Jexl.eval("value|double", %{"value" => 5})
# => {:ok, 10}

MyApp.Jexl.eval("add(2, 3)")
# => {:ok, 5}
```

Per-call opts merge on top of (and can override) module-level defaults:

```elixir
# Override the default "double" for this call only
MyApp.Jexl.eval("value|double", %{"value" => 5}, transforms: %{"double" => fn v -> v * 3 end})
# => {:ok, 15}

# Add a one-off transform alongside the defaults
MyApp.Jexl.eval("value|triple", %{"value" => 5}, transforms: %{"triple" => fn v -> v * 3 end})
# => {:ok, 15}
```

## Error Handling

```elixir
ExJexl.eval("1 + + 2")
# => {:error, "expected end of string"}

ExJexl.eval("10 / 0")
# => {:error, "Division by zero"}

# eval! raises on error
ExJexl.eval!("10 / 0")
# => ** (RuntimeError) JEXL evaluation error: "Division by zero"
```

## Testing

```bash
mix test
```

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

- Built with [NimbleParsec](https://github.com/dashbitco/nimble_parsec)
- Inspired by the [JEXL specification](https://github.com/TomFrost/Jexl)
