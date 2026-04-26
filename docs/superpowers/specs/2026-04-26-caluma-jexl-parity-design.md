# Caluma JEXL parity for ex_jexl

**Status:** approved (design)
**Date:** 2026-04-26

## Goal

Make `ex_jexl` a drop-in replacement for the JEXL evaluator used inside [projectcaluma/caluma](https://github.com/projectcaluma/caluma) (`caluma/caluma_core/jexl.py` + form/workflow extensions). Anyone porting Caluma to Elixir should be able to use `ex_jexl` without re-implementing core JEXL semantics.

## Non-goals

- **No domain-specific transforms or validators in ex_jexl.** `answer`, `task`, `tasks`, `groups` and the validators that go with them belong in the host application (e.g. an Elixir port of Caluma).
- **No parsed-AST cache in ex_jexl.** The host can wrap `ExJexl.Parser.parse/1` if it wants caching, but ex_jexl will not ship one.
- **No expression-stack feature for `debug`.** Caluma's `_expr_stack` lets `debug` log the surrounding expression; we drop that and only log the label + value.

## Decisions

- **D1.** Match Caluma semantics exactly — including breaking changes to existing built-ins (`length`, `first`, `last`, `floor`, `ceil`, `round`, `abs`).
- **D2.** Use Erlang/OTP `:json` (stdlib in OTP 27+). Bump `elixir: "~> 1.18"`. No new runtime deps.
- **D3.** ex_jexl exposes generic primitives — public AST format, AST walker, transform finder, validator plug-in API. Domain logic stays out.
- **D4.** Validator API yields all errors at once (no fail-fast), matching Caluma's generator-based pattern.

## Architecture

### Module layout

```
lib/ex_jexl/
  parser.ex       (existing — unchanged)
  evaluator.ex    (existing — minor wiring for new built-ins)
  helpers.ex      (existing — unchanged)
  transforms.ex   (existing — new built-ins, behavior fixes, safe/1 wrapper)
  ast.ex          NEW — AST walker + transform-finder helpers
  validator.ex    NEW — validation plug-in API
ex_jexl.ex        (existing — `use ExJexl` extended with `validators:` opt)
```

### Public API surface

```elixir
# Eval (unchanged)
ExJexl.eval(expr, ctx, opts)
ExJexl.eval!(expr, ctx, opts)

# Parse (already public — AST format becomes documented contract)
ExJexl.Parser.parse(expr) :: {:ok, ast} | {:error, reason}

# AST analysis (new)
ExJexl.AST.prewalk(ast, acc, fun)
ExJexl.AST.postwalk(ast, acc, fun)
ExJexl.AST.walk(ast, acc, fun)             # read-only fold
ExJexl.AST.find_transforms(ast, name)      # name :: :any | String.t() | [String.t()]
# returns [%{name: String.t(), subject: ast, args: [ast]}]

# Validation (new)
ExJexl.Validator.validate(expr, validators \\ [])
ExJexl.Validator.validate_ast(ast, validators \\ [])
# returns {:ok, [error_string]} | {:error, parse_error}
```

### `use ExJexl` extension

Existing options: `transforms:`, `functions:`. Add `validators:`. Adds a `validate/1`/`validate/2` function on the wrapping module that uses module-level validators by default and merges per-call extras.

```elixir
defmodule MyApp.Jexl do
  use ExJexl,
    transforms: %{...},
    functions: %{...},
    validators: [&MyApp.Jexl.Validators.answer/1]
end

MyApp.Jexl.validate(expr)
MyApp.Jexl.validate(expr, validators: [&extra/1])
```

## AST format (public contract)

```
{:integer, integer}
{:float, float}
{:string, binary}
{:boolean, boolean}
{:null, nil}
{:identifier, name :: binary}
{:array, [ast]}
{:object, [{:pair, [key_ast, value_ast]}, ...]}
{:property_access, [obj_ast, {:identifier, prop}]}
{:bracket_access, [obj_ast, key_ast]}
{:ternary, [cond_ast, true_ast, false_ast]}
{:binary_op, [op_atom, left_ast, right_ast]}
{:unary, [{:op, :!}, expr_ast]}
{:function_call, [{:identifier, name} | arg_asts]}
```

**Pipe / transform encoding.** `a|x|y` parses left-associative: `{:binary_op, [:|, {:binary_op, [:|, a, x_call]}, y_call]}`. The transform call on the right side is either:
- `{:identifier, name}` — no args
- `{:function_call, [{:identifier, name} | args]}` — with args

`ExJexl.AST.find_transforms/2` abstracts this so callers don't have to know the encoding.

## Built-in transforms

### New transforms

| Name | Signature | Behavior |
|---|---|---|
| `mapby` | `arr\|mapby(k1, k2, ...)` | One key: `[obj[k] for obj in arr]`. Multiple keys: `[[obj[k] for k in keys] for obj in arr]`. Non-list subject → `nil`. |
| `stringify` | `obj\|stringify` | `:json.encode(obj) \|> IO.iodata_to_binary()`. Compact (no whitespace) — byte-for-byte match with `ember-caluma`. |
| `min` | `arr\|min` | `Enum.min` after `filter_numbers/1`. Empty result → `nil`. |
| `max` | `arr\|max` | `Enum.max` after `filter_numbers/1`. Empty result → `nil`. |
| `sum` | `arr\|sum` | `Enum.sum` after `filter_numbers/1`. Empty result → `0`. |
| `avg` | `arr\|avg` | `sum / length` after filter. Empty → `nil`. |
| `debug` | `val\|debug` or `val\|debug('label')` | `Logger.info("[JEXL debug] #{label}: #{inspect(val)}")` (or sans label), returns `val` unchanged. |

### Semantic fixes (BREAKING)

| Name | Old | New |
|---|---|---|
| `length` | `0` for unsupported | `nil` |
| `first` | raises on non-list | `nil` |
| `last` | raises on non-list | `nil` |
| `abs` | raises on non-number | `nil` |
| `floor` | `trunc(n)` (wrong for negatives) | `:math.floor/1 \|> trunc/1` |
| `ceil` | ad-hoc impl | `:math.ceil/1 \|> trunc/1` |
| `round` | `Kernel.round/1` (banker's) + no args | half-up: `trunc(n * 10^p + 0.5) / 10^p`. Accepts optional `ndigits` arg (default 0). |

### Helpers

```elixir
defp filter_numbers(arr) when is_list(arr) do
  Enum.filter(arr, fn x -> is_number(x) and not (is_float(x) and x != x) end)
end
defp filter_numbers(_), do: []
```

A nil-on-rescue helper (call shape decided at implementation time) wraps the body of: `min`, `max`, `sum`, `avg`, `ceil`, `floor`, `round`, `abs`. Caluma traps `TypeError/ValueError/ZeroDivisionError`. The Elixir analogues are `ArithmeticError`, `ArgumentError`, `FunctionClauseError` — those three are caught and converted to `nil`. Other exceptions propagate.

### Return shape

`Transforms.apply_transform/3` continues to return `{:ok, val} | {:error, reason}`. New transforms return `{:ok, nil}` for type mismatches (not `{:error, _}`). Unknown transform names still return `{:error, "Unknown transform: ..."}`.

## `ExJexl.AST`

### Walkers

`prewalk/3` and `postwalk/3` mirror `Macro.prewalk/3` and `Macro.postwalk/3`:

```elixir
@spec prewalk(ast, acc, (node, acc -> {node, acc})) :: {ast, acc}
@spec postwalk(ast, acc, (node, acc -> {node, acc})) :: {ast, acc}
```

Every tuple in the AST format is a node. Recursion happens into:
- `:array` elements
- `:object` pair values (keys are not walked — they are atoms-like identifiers)
- `:property_access` first child (object)
- `:bracket_access` both children
- `:ternary` all three branches
- `:binary_op` left and right
- `:unary` expr (not the `{:op, _}` tag)
- `:function_call` argument asts (not the `{:identifier, name}` head)

`walk/3` is a read-only fold convenience:

```elixir
@spec walk(ast, acc, (node, acc -> acc)) :: acc
def walk(ast, acc, fun) do
  {_, final} = prewalk(ast, acc, fn node, a -> {node, fun.(node, a)} end)
  final
end
```

### `find_transforms/2`

```elixir
@spec find_transforms(ast, :any | String.t() | [String.t()]) ::
  [%{name: String.t(), subject: ast, args: [ast]}]
```

Walks AST, detects pipe RHS pattern, emits one match per transform call. Recurses through chained pipes — `a|x|y` yields `[%{name: "x", subject: a, args: []}, %{name: "y", subject: {:binary_op, [:|, a, ...]}, args: []}]`. Filter by `name`:
- `:any` — every transform call
- `"name"` — exact match
- `["a", "b"]` — any-of match

### Worked example: dependency extraction

A Caluma-style host writes (in its own code, not in ex_jexl):

```elixir
def extract_referenced_questions(expr) do
  with {:ok, ast} <- ExJexl.Parser.parse(expr) do
    refs =
      ast
      |> ExJexl.AST.find_transforms("answer")
      |> Enum.flat_map(fn
        %{subject: {:string, slug}} -> [slug]
        _ -> []
      end)

    {:ok, refs}
  end
end

def extract_referenced_mapby_questions(expr) do
  with {:ok, ast} <- ExJexl.Parser.parse(expr) do
    refs =
      ast
      |> ExJexl.AST.find_transforms("mapby")
      |> Enum.filter(&mapby_subject_is_answer?/1)
      |> Enum.flat_map(fn %{args: args} ->
        for {:string, slug} <- args, do: slug
      end)

    {:ok, refs}
  end
end

defp mapby_subject_is_answer?(%{subject: subject}) do
  case subject do
    {:binary_op, [:|, _, {:identifier, "answer"}]} -> true
    {:binary_op, [:|, _, {:function_call, [{:identifier, "answer"} | _]}]} -> true
    _ -> false
  end
end
```

ex_jexl knows nothing about `answer`, `mapby`, slugs, or questions.

## `ExJexl.Validator`

### Types

```elixir
@type ast :: tuple()
@type validator :: (ast -> [String.t()])
@type result :: {:ok, [String.t()]} | {:error, term()}
```

### API

```elixir
@spec validate(String.t(), [validator]) :: result
def validate(expr, validators \\ []) do
  with {:ok, ast} <- ExJexl.Parser.parse(expr) do
    {:ok, validate_ast(ast, validators)}
  end
end

@spec validate_ast(ast, [validator]) :: [String.t()]
def validate_ast(ast, validators \\ []) do
  Enum.flat_map(validators, fn v -> v.(ast) end)
end
```

### Semantics

- Empty validator list → `{:ok, []}` for any parseable expression.
- Each validator runs over the full AST. Validators are independent; errors collected, no fail-fast.
- Validator that returns non-list → crash. We do not silently coerce. (Validators are author-controlled code; bad return is a bug, not a validation outcome.)
- Parse failure short-circuits: returns `{:error, parse_error}` without running validators. Caller decides how to surface that. (Unlike Caluma, we don't yield the parse error as a string — separating the two error classes is more useful in Elixir.)

### Built-in validators

**None.** Parse-error reporting is structural (`{:error, _}` from `parse`), not a validator.

### `use ExJexl` integration

```elixir
defmodule MyApp.Jexl do
  use ExJexl,
    transforms: %{...},
    validators: [&V.answer/1, &V.task/1]
end

# Generated on the wrapping module:
# - eval/1, eval/2, eval/3 (existing)
# - eval!/1, eval!/2, eval!/3 (existing)
# - validate/1, validate/2 (new)

MyApp.Jexl.validate(expr)
# uses module-level validators

MyApp.Jexl.validate(expr, validators: [&extra/1])
# merges: module-level ++ per-call
```

Merge semantics for `validators:` mirror those for `transforms:`/`functions:`: the per-call list is appended after the module-level list. Order matters only for the order of returned errors, which is documented as "in validator order, then in walk order within each validator".

## Mix.exs / dependencies

- `elixir: "~> 1.18"` — required for OTP 27+ guarantee.
- No new runtime deps. `:json` is stdlib in OTP 27+.
- No new dev/test deps.
- `application/0`: keep `:logger` in `extra_applications` (already present).
- README "Installation" section adds an OTP 27+ note.

## Tests

### Existing test file

`test/ex_jexl_test.exs` — extend with:

| Area | Cases |
|---|---|
| New transforms | `mapby` single-key/multi-key/non-list-nil; `stringify` (compare to `:json.encode` roundtrip and assert no whitespace); `min`/`max`/`sum`/`avg` (mixed types filter, NaN filter, empty list, nil-on-non-list); `debug` returns value unchanged + emits `Logger.info` (use `ExUnit.CaptureLog`) |
| Semantic fixes | `length` nil for unsupported; `first`/`last` nil on non-list; `floor(-1.5) == -2`; `ceil(-1.5) == -1`; `round(2.5) == 3`; `round(0.5) == 1`; `round(1.5) == 2` (half-up — banker's would give 2/0/2); `round(1.234, 2) == 1.23`; `abs("x") == nil` |
| Error trap | Each `safe`-wrapped transform returns `nil` for type mismatches |
| `use ExJexl` | `validators:` option exposes `validate/1` and `validate/2`; merge order with per-call validators |

### New test files

- `test/ex_jexl/ast_test.exs` — prewalk/postwalk/walk for every AST node type (literals, identifier, array, object, property_access, bracket_access, ternary, binary_op, unary, function_call); `find_transforms/2` for `:any`, single name, list of names; chained pipes (`a|x|y`); transforms inside ternary, array, object; expression with no transforms.
- `test/ex_jexl/validator_test.exs` — empty validators, single validator, multiple validators (all errors collected), parse error short-circuit returns `{:error, _}`, `validate_ast/2` variant, validator that uses `ExJexl.AST.find_transforms/2`.

## Migration / changelog

`CHANGELOG.md` entry for the next version:

```
## [next]

### Breaking changes
- Built-in transform error semantics changed to nil-on-error matching Caluma pyjexl.
  - `length` on unsupported types now returns `nil` instead of `0`.
  - `first`/`last`/`abs` on type mismatches now return `nil` instead of raising.
- `floor` is now correct for negative floats (uses `:math.floor/1`).
- `ceil` is now correct for negative floats (uses `:math.ceil/1`).
- `round` is now half-up (matching Caluma / JS), not half-to-even (banker's).
  Accepts an optional decimal-places argument: `n|round(2)`.
- Elixir 1.18+ / OTP 27+ required.

### New
- `mapby`, `stringify`, `min`, `max`, `sum`, `avg`, `debug` transforms.
- `ExJexl.AST` module — public AST walker + transform finder.
- `ExJexl.Validator` module — pluggable validator API.
- `use ExJexl` accepts `validators:` option.
- Documented public AST format.
```

`README.md` updates:
- New "Caluma compatibility" section listing what's parity and what's intentionally not (domain transforms, AST cache).
- Extend "Custom Transforms and Functions" with a validator example.
- Document AST format + walker for downstream consumers in a new "Analyzing expressions" section.
