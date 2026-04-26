# Caluma JEXL parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `ex_jexl` to parity with Caluma's pyjexl semantics: ship the missing built-in transforms, fix existing transforms to match Caluma's nil-on-error behavior, and expose generic AST + validation primitives so a Caluma-style host can build domain analyzers/validators on top.

**Architecture:** All work lives inside the existing `ExJexl.*` namespace. `lib/ex_jexl/transforms.ex` gains new transforms (`mapby`, `stringify`, `min`, `max`, `sum`, `avg`, `debug`) and semantic fixes to existing ones (`length`, `first`, `last`, `abs`, `floor`, `ceil`, `round`). Two new modules — `ExJexl.AST` (walker + transform finder) and `ExJexl.Validator` (validator plug-in API) — give downstream tools structured ways to inspect and validate expressions. `use ExJexl` grows a `validators:` option. No new runtime dependencies; `:json` from OTP 27+ replaces a Jason dep.

**Tech Stack:** Elixir 1.18+, OTP 27+, NimbleParsec (existing), `:json` (stdlib), `Logger` (stdlib), ExUnit + ExUnit.CaptureLog for tests.

**Spec:** `docs/superpowers/specs/2026-04-26-caluma-jexl-parity-design.md`

---

## File Structure

**Modify:**
- `mix.exs` — bump elixir requirement to ~> 1.18.
- `lib/ex_jexl.ex` — extend `__using__` macro with `validators:` option.
- `lib/ex_jexl/transforms.ex` — add new transforms + helpers; fix existing semantics.
- `test/ex_jexl_test.exs` — extend with tests for new transforms + semantic-fix regressions + `use ExJexl` validators.
- `CHANGELOG.md` — add entry for next version.
- `README.md` — Caluma compat section, AST/Validator sections.

**Create:**
- `lib/ex_jexl/ast.ex` — `prewalk/3`, `postwalk/3`, `walk/3`, `find_transforms/2`.
- `lib/ex_jexl/validator.ex` — `validate/2`, `validate_ast/2`.
- `test/ex_jexl/ast_test.exs` — tests for AST module.
- `test/ex_jexl/validator_test.exs` — tests for Validator module.

---

## Task 1: Bump Elixir requirement to 1.18

**Files:**
- Modify: `mix.exs:11`

- [ ] **Step 1: Update elixir version**

Change `elixir: "~> 1.15"` to `elixir: "~> 1.18"` on line 11 of `mix.exs`.

- [ ] **Step 2: Run tests to confirm everything still works**

Run: `mix deps.get && mix test`
Expected: all existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add mix.exs
git commit -m "chore: require Elixir ~> 1.18 / OTP 27+ for :json stdlib"
```

---

## Task 2: Add `mapby` transform

**Files:**
- Modify: `lib/ex_jexl/transforms.ex`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add inside the `describe "transforms"` block in `test/ex_jexl_test.exs`:

```elixir
test "mapby with single key" do
  ctx = %{"items" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}
  assert {:ok, [1, 3]} = ExJexl.eval("items|mapby('a')", ctx)
end

test "mapby with multiple keys" do
  ctx = %{"items" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}
  assert {:ok, [[1, 2], [3, 4]]} = ExJexl.eval("items|mapby('a', 'b')", ctx)
end

test "mapby on non-list returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|mapby('a')", %{"x" => "not a list"})
end

test "mapby with no args returns nil" do
  assert {:ok, nil} = ExJexl.eval("items|mapby", %{"items" => [%{"a" => 1}]})
end

test "mapby missing key yields nil entries" do
  ctx = %{"items" => [%{"a" => 1}, %{"b" => 2}]}
  assert {:ok, [1, nil]} = ExJexl.eval("items|mapby('a')", ctx)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test --only line:0 test/ex_jexl_test.exs` (or just `mix test test/ex_jexl_test.exs`)
Expected: 5 new tests fail with "Unknown transform: mapby".

- [ ] **Step 3: Implement mapby in transforms.ex**

Add these clauses to `lib/ex_jexl/transforms.ex`, placed after the existing `flatten` clause but before the catch-all `apply_transform(name, _value, _args)` at the bottom:

```elixir
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
```

Add this private helper at the bottom of the module (above the closing `end`):

```elixir
  defp mapby_value(obj, key) when is_map(obj) do
    Map.get(obj, key) || Map.get(obj, to_string(key))
  end

  defp mapby_value(_obj, _key), do: nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl_test.exs`
Expected: all 5 mapby tests pass; no regressions.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "feat(transforms): add mapby transform"
```

---

## Task 3: Add `stringify` transform

**Files:**
- Modify: `lib/ex_jexl/transforms.ex`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add inside the `describe "transforms"` block in `test/ex_jexl_test.exs`:

```elixir
test "stringify on map produces compact JSON" do
  ctx = %{"obj" => %{"a" => 1, "b" => "two"}}
  assert {:ok, json} = ExJexl.eval("obj|stringify", ctx)
  # Compact JSON: no whitespace
  refute json =~ " "
  # Round-trip via :json
  assert :json.decode(json) == %{"a" => 1, "b" => "two"}
end

test "stringify on list" do
  assert {:ok, "[1,2,3]"} = ExJexl.eval("nums|stringify", %{"nums" => [1, 2, 3]})
end

test "stringify on string" do
  assert {:ok, "\"hello\""} = ExJexl.eval("s|stringify", %{"s" => "hello"})
end

test "stringify on number" do
  assert {:ok, "42"} = ExJexl.eval("n|stringify", %{"n" => 42})
end

test "stringify on null" do
  assert {:ok, "null"} = ExJexl.eval("x|stringify", %{"x" => nil})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 5 new tests fail with "Unknown transform: stringify".

- [ ] **Step 3: Implement stringify in transforms.ex**

Add this clause to `lib/ex_jexl/transforms.ex` (above the catch-all):

```elixir
  def apply_transform("stringify", value, _args) do
    {:ok, IO.iodata_to_binary(:json.encode(value))}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl_test.exs`
Expected: all 5 stringify tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "feat(transforms): add stringify transform using :json stdlib"
```

---

## Task 4: Add `min`/`max`/`sum`/`avg` transforms with `filter_numbers` helper

**Files:**
- Modify: `lib/ex_jexl/transforms.ex`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add inside the `describe "transforms"` block in `test/ex_jexl_test.exs`:

```elixir
test "min on number list" do
  assert {:ok, 1} = ExJexl.eval("nums|min", %{"nums" => [3, 1, 4, 1, 5]})
end

test "min filters non-numbers" do
  assert {:ok, 2} = ExJexl.eval("nums|min", %{"nums" => [2, "x", nil, 5]})
end

test "min on empty list returns nil" do
  assert {:ok, nil} = ExJexl.eval("nums|min", %{"nums" => []})
end

test "min on non-list returns nil" do
  assert {:ok, nil} = ExJexl.eval("nums|min", %{"nums" => "not a list"})
end

test "max on number list" do
  assert {:ok, 5} = ExJexl.eval("nums|max", %{"nums" => [3, 1, 4, 1, 5]})
end

test "max filters non-numbers" do
  assert {:ok, 5} = ExJexl.eval("nums|max", %{"nums" => [3, "x", 5, nil]})
end

test "max on empty list returns nil" do
  assert {:ok, nil} = ExJexl.eval("nums|max", %{"nums" => []})
end

test "sum on number list" do
  assert {:ok, 15} = ExJexl.eval("nums|sum", %{"nums" => [1, 2, 3, 4, 5]})
end

test "sum filters non-numbers" do
  assert {:ok, 6} = ExJexl.eval("nums|sum", %{"nums" => [1, "x", 2, nil, 3]})
end

test "sum on empty list returns 0" do
  assert {:ok, 0} = ExJexl.eval("nums|sum", %{"nums" => []})
end

test "sum on non-list returns 0" do
  # filter_numbers/1 yields [] for non-lists; Enum.sum([]) is 0.
  assert {:ok, 0} = ExJexl.eval("nums|sum", %{"nums" => "x"})
end

test "avg on number list" do
  assert {:ok, 3.0} = ExJexl.eval("nums|avg", %{"nums" => [1, 2, 3, 4, 5]})
end

test "avg filters non-numbers" do
  assert {:ok, 2.0} = ExJexl.eval("nums|avg", %{"nums" => [1, "x", 2, nil, 3]})
end

test "avg on empty list returns nil" do
  assert {:ok, nil} = ExJexl.eval("nums|avg", %{"nums" => []})
end

test "avg on non-list returns nil" do
  assert {:ok, nil} = ExJexl.eval("nums|avg", %{"nums" => "x"})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 15 new tests fail with "Unknown transform: ..." for min/max/sum/avg.

- [ ] **Step 3: Implement min/max/sum/avg in transforms.ex**

Add these clauses to `lib/ex_jexl/transforms.ex` (above the catch-all):

```elixir
  def apply_transform("min", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> {:ok, Enum.min(nums)}
    end
  end

  def apply_transform("max", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> {:ok, Enum.max(nums)}
    end
  end

  def apply_transform("sum", value, _args) do
    {:ok, Enum.sum(filter_numbers(value))}
  end

  def apply_transform("avg", value, _args) do
    case filter_numbers(value) do
      [] -> {:ok, nil}
      nums -> {:ok, Enum.sum(nums) / length(nums)}
    end
  end
```

Add these private helpers at the bottom of the module (alongside `mapby_value`):

```elixir
  defp filter_numbers(arr) when is_list(arr) do
    Enum.filter(arr, &valid_number?/1)
  end

  defp filter_numbers(_), do: []

  defp valid_number?(x) when is_integer(x), do: true
  defp valid_number?(x) when is_float(x), do: x == x  # filters NaN
  defp valid_number?(_), do: false
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl_test.exs`
Expected: all 15 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "feat(transforms): add min/max/sum/avg with number filter"
```

---

## Task 5: Add `debug` transform

**Files:**
- Modify: `lib/ex_jexl/transforms.ex`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add inside the `describe "transforms"` block in `test/ex_jexl_test.exs`:

```elixir
test "debug returns value unchanged" do
  assert {:ok, 42} = ExJexl.eval("x|debug", %{"x" => 42})
end

test "debug logs without label" do
  import ExUnit.CaptureLog
  log = capture_log(fn -> ExJexl.eval("x|debug", %{"x" => 42}) end)
  assert log =~ "[JEXL debug]"
  assert log =~ "42"
end

test "debug with label includes label in log" do
  import ExUnit.CaptureLog
  log = capture_log(fn -> ExJexl.eval("x|debug('myvar')", %{"x" => 42}) end)
  assert log =~ "myvar"
  assert log =~ "42"
end

test "debug returns value unchanged with label" do
  assert {:ok, [1, 2]} = ExJexl.eval("x|debug('arr')", %{"x" => [1, 2]})
end
```

The first test in `test/test_helper.exs` should already enable Logger output for tests; verify by running existing tests pass first. If `ExUnit.CaptureLog` isn't already imported, the per-test `import` above handles it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 4 new tests fail with "Unknown transform: debug".

- [ ] **Step 3: Implement debug in transforms.ex**

Add `require Logger` near the top of `lib/ex_jexl/transforms.ex`, just below the `import ExJexl.Helpers` line:

```elixir
  require Logger
```

Add these clauses to `lib/ex_jexl/transforms.ex` (above the catch-all):

```elixir
  def apply_transform("debug", value, []) do
    Logger.info("[JEXL debug] value = #{inspect(value)}")
    {:ok, value}
  end

  def apply_transform("debug", value, [label]) do
    Logger.info("[JEXL debug] #{label}: #{inspect(value)}")
    {:ok, value}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl_test.exs`
Expected: all 4 debug tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "feat(transforms): add debug transform with optional label"
```

---

## Task 6: Fix `length` semantics — nil for unsupported types

**Files:**
- Modify: `lib/ex_jexl/transforms.ex:15-22`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests + update existing**

In `test/ex_jexl_test.exs`, add to the `describe "transforms"` block:

```elixir
test "length on number returns nil (was 0)" do
  assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => 42})
end

test "length on nil returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => nil})
end

test "length on boolean returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => true})
end
```

If any existing test asserts `length` on unsupported types returns `0`, change those to expect `nil` (search for `|length` in `test/ex_jexl_test.exs` and review).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 3 new tests fail (returning `0` instead of `nil`).

- [ ] **Step 3: Update length implementation**

In `lib/ex_jexl/transforms.ex`, replace the existing `apply_transform("length", ...)` clause:

```elixir
  def apply_transform("length", value, _args) do
    case value do
      list when is_list(list) -> {:ok, length(list)}
      string when is_binary(string) -> {:ok, String.length(string)}
      map when is_map(map) -> {:ok, map_size(map)}
      _ -> {:ok, nil}
    end
  end
```

(Only the last clause changes: `{:ok, 0}` → `{:ok, nil}`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "fix(transforms)!: length returns nil for unsupported types

BREAKING: length on numbers/booleans/nil now returns nil instead of 0,
matching Caluma pyjexl semantics."
```

---

## Task 7: Fix `first`/`last` — nil on non-list

**Files:**
- Modify: `lib/ex_jexl/transforms.ex:24-36`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add in `test/ex_jexl_test.exs`:

```elixir
test "first on non-list returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|first", %{"x" => "not a list"})
end

test "first on number returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|first", %{"x" => 42})
end

test "last on non-list returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|last", %{"x" => "not a list"})
end

test "last on map returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|last", %{"x" => %{"a" => 1}})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 4 new tests fail (raise FunctionClauseError or similar).

- [ ] **Step 3: Add catch-all clauses**

In `lib/ex_jexl/transforms.ex`, immediately after the existing `apply_transform("first", list, _args) when is_list(list) do ... end` clause, add:

```elixir
  def apply_transform("first", _value, _args), do: {:ok, nil}
```

Similarly, immediately after the existing `apply_transform("last", list, _args) when is_list(list) do ... end` clause, add:

```elixir
  def apply_transform("last", _value, _args), do: {:ok, nil}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "fix(transforms)!: first/last return nil on non-list

BREAKING: previously raised FunctionClauseError on non-list inputs."
```

---

## Task 8: Fix `abs` — nil on non-number

**Files:**
- Modify: `lib/ex_jexl/transforms.ex:86-88`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add in `test/ex_jexl_test.exs`:

```elixir
test "abs on string returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|abs", %{"x" => "hello"})
end

test "abs on nil returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|abs", %{"x" => nil})
end

test "abs on negative number works" do
  assert {:ok, 5} = ExJexl.eval("x|abs", %{"x" => -5})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: 2 new tests fail (raise on non-number).

- [ ] **Step 3: Add catch-all for abs**

In `lib/ex_jexl/transforms.ex`, after the existing `apply_transform("abs", number, _args) when is_number(number) ...` clause, add:

```elixir
  def apply_transform("abs", _value, _args), do: {:ok, nil}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "fix(transforms)!: abs returns nil on non-number

BREAKING: previously raised on non-number inputs."
```

---

## Task 9: Fix `floor`/`ceil` for negatives

**Files:**
- Modify: `lib/ex_jexl/transforms.ex:94-100`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add in `test/ex_jexl_test.exs`:

```elixir
test "floor of negative float" do
  assert {:ok, -2} = ExJexl.eval("x|floor", %{"x" => -1.5})
end

test "floor of positive float" do
  assert {:ok, 1} = ExJexl.eval("x|floor", %{"x" => 1.7})
end

test "floor of integer" do
  assert {:ok, 5} = ExJexl.eval("x|floor", %{"x" => 5})
end

test "floor of non-number returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|floor", %{"x" => "abc"})
end

test "ceil of negative float" do
  assert {:ok, -1} = ExJexl.eval("x|ceil", %{"x" => -1.5})
end

test "ceil of positive float" do
  assert {:ok, 2} = ExJexl.eval("x|ceil", %{"x" => 1.2})
end

test "ceil of integer" do
  assert {:ok, 5} = ExJexl.eval("x|ceil", %{"x" => 5})
end

test "ceil of non-number returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|ceil", %{"x" => "abc"})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: `floor(-1.5)` returns `-1` (wrong) instead of `-2`. `ceil` similar.

- [ ] **Step 3: Replace floor/ceil implementations**

In `lib/ex_jexl/transforms.ex`, replace the existing `apply_transform("floor", ...)` and `apply_transform("ceil", ...)` clauses with:

```elixir
  def apply_transform("floor", n, _args) when is_number(n) do
    {:ok, trunc(:math.floor(n * 1.0))}
  end

  def apply_transform("floor", _value, _args), do: {:ok, nil}

  def apply_transform("ceil", n, _args) when is_number(n) do
    {:ok, trunc(:math.ceil(n * 1.0))}
  end

  def apply_transform("ceil", _value, _args), do: {:ok, nil}
```

The `* 1.0` coerces integers to floats so `:math.floor` / `:math.ceil` accept them on all OTP versions.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "fix(transforms)!: floor/ceil correct for negative numbers

BREAKING: floor/ceil previously used trunc which is wrong for negatives.
Now uses :math.floor/:math.ceil. Returns nil on non-number."
```

---

## Task 10: Fix `round` — half-up + accept ndigits arg

**Files:**
- Modify: `lib/ex_jexl/transforms.ex:90-92`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add in `test/ex_jexl_test.exs`:

```elixir
test "round half-up: 0.5 rounds to 1" do
  assert {:ok, 1.0} = ExJexl.eval("x|round", %{"x" => 0.5})
end

test "round half-up: 1.5 rounds to 2 (not banker's 2)" do
  assert {:ok, 2.0} = ExJexl.eval("x|round", %{"x" => 1.5})
end

test "round half-up: 2.5 rounds to 3 (not banker's 2)" do
  assert {:ok, 3.0} = ExJexl.eval("x|round", %{"x" => 2.5})
end

test "round half-up negative: -0.5 rounds to 0 (towards positive)" do
  assert {:ok, 0.0} = ExJexl.eval("x|round", %{"x" => -0.5})
end

test "round half-up negative: -1.5 rounds to -1 (towards positive)" do
  assert {:ok, -1.0} = ExJexl.eval("x|round", %{"x" => -1.5})
end

test "round with decimal places" do
  assert {:ok, 1.23} = ExJexl.eval("x|round(2)", %{"x" => 1.234})
end

test "round with decimal places half-up" do
  assert {:ok, 1.24} = ExJexl.eval("x|round(2)", %{"x" => 1.235})
end

test "round on integer returns float" do
  assert {:ok, 5.0} = ExJexl.eval("x|round", %{"x" => 5})
end

test "round on non-number returns nil" do
  assert {:ok, nil} = ExJexl.eval("x|round", %{"x" => "abc"})
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: half-up tests fail (Kernel.round is banker's). `round(2)` with ndigits unsupported.

- [ ] **Step 3: Replace round implementation**

In `lib/ex_jexl/transforms.ex`, replace the existing `apply_transform("round", ...)` clause:

```elixir
  def apply_transform("round", n, args) when is_number(n) do
    ndigits =
      case args do
        [] -> 0
        [d] when is_integer(d) -> d
        _ -> 0
      end

    power = :math.pow(10, ndigits)
    {:ok, :math.floor(n * power + 0.5) / power}
  end

  def apply_transform("round", _value, _args), do: {:ok, nil}
```

This matches Caluma's `_round_compat`: `floor((n * 10^p) + 0.5) / 10^p`. Returns float in all cases.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/transforms.ex test/ex_jexl_test.exs
git commit -m "fix(transforms)!: round is half-up and accepts ndigits

BREAKING: round was banker's rounding via Kernel.round. Now matches
Caluma/JS half-up semantics. Optional decimal-places arg added.
Always returns float. Returns nil on non-number."
```

---

## Task 11: Create `ExJexl.AST` — `prewalk/3`

**Files:**
- Create: `lib/ex_jexl/ast.ex`
- Create: `test/ex_jexl/ast_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/ex_jexl/ast_test.exs`:

```elixir
defmodule ExJexl.ASTTest do
  use ExUnit.Case, async: true

  alias ExJexl.AST
  alias ExJexl.Parser

  describe "prewalk/3" do
    test "visits literal" do
      ast = {:integer, 42}
      {result_ast, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert result_ast == {:integer, 42}
      assert acc == [{:integer, 42}]
    end

    test "visits identifier" do
      ast = {:identifier, "x"}
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert acc == [{:identifier, "x"}]
    end

    test "visits array elements" do
      {:ok, ast} = Parser.parse("[1, 2, 3]")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      # Outer array + 3 integers
      assert {:array, _} = List.last(acc)
      assert {:integer, 1} in acc
      assert {:integer, 2} in acc
      assert {:integer, 3} in acc
    end

    test "visits object pair values" do
      {:ok, ast} = Parser.parse(~s({"a": 1, "b": 2}))
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:integer, 1} in acc
      assert {:integer, 2} in acc
    end

    test "visits property access object" do
      {:ok, ast} = Parser.parse("user.name")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "user"} in acc
    end

    test "visits bracket access object and key" do
      {:ok, ast} = Parser.parse("data[idx]")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "data"} in acc
      assert {:identifier, "idx"} in acc
    end

    test "visits ternary branches" do
      {:ok, ast} = Parser.parse("x ? a : b")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "x"} in acc
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "visits binary_op children" do
      {:ok, ast} = Parser.parse("a + b")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "visits unary expression child" do
      {:ok, ast} = Parser.parse("!x")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "x"} in acc
    end

    test "visits function call args (not the head identifier)" do
      {:ok, ast} = Parser.parse("f(a, b)")
      {_, acc} = AST.prewalk(ast, [], fn node, a -> {node, [node | a]} end)
      assert {:identifier, "a"} in acc
      assert {:identifier, "b"} in acc
    end

    test "transforms via the function" do
      {:ok, ast} = Parser.parse("x + 1")
      {new_ast, _} = AST.prewalk(ast, nil, fn
        {:integer, n}, a -> {{:integer, n + 100}, a}
        node, a -> {node, a}
      end)
      # The 1 should now be 101
      assert match?({:binary_op, [:+, {:identifier, "x"}, {:integer, 101}]}, new_ast)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: tests fail with "ExJexl.AST.prewalk/3 is undefined" (module doesn't exist yet).

- [ ] **Step 3: Implement ExJexl.AST with prewalk**

Create `lib/ex_jexl/ast.ex`:

```elixir
defmodule ExJexl.AST do
  @moduledoc """
  AST inspection utilities for ex_jexl expressions.

  The AST is the tuple-based intermediate representation produced by
  `ExJexl.Parser.parse/1`. This module provides walkers and helpers
  for downstream tooling — analyzers, validators, dependency extraction.

  ## AST format

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

  Pipe / transform encoding: `a|x|y` parses left-associative as
  `{:binary_op, [:|, {:binary_op, [:|, a, x_call]}, y_call]}` where the
  transform call (the right side of each pipe) is either `{:identifier, name}`
  for a no-arg transform or `{:function_call, [{:identifier, name} | args]}`
  for a transform with arguments. Use `find_transforms/2` to abstract over
  this encoding.
  """

  @type ast :: tuple()

  @doc """
  Walks the AST in pre-order, applying `fun` to each node and threading `acc`.

  `fun` receives `(node, acc)` and returns `{node, acc}`. Mirrors `Macro.prewalk/3`.
  """
  @spec prewalk(ast, acc, (ast, acc -> {ast, acc})) :: {ast, acc} when acc: any
  def prewalk(ast, acc, fun) do
    {new_ast, new_acc} = fun.(ast, acc)
    walk_children(new_ast, new_acc, &prewalk(&1, &2, fun))
  end

  defp walk_children({:array, elements}, acc, walker) do
    {new_elements, acc} = Enum.map_reduce(elements, acc, walker)
    {{:array, new_elements}, acc}
  end

  defp walk_children({:object, pairs}, acc, walker) do
    {new_pairs, acc} =
      Enum.map_reduce(pairs, acc, fn {:pair, [k, v]}, a ->
        {new_v, a2} = walker.(v, a)
        {{:pair, [k, new_v]}, a2}
      end)

    {{:object, new_pairs}, acc}
  end

  defp walk_children({:property_access, [obj, prop]}, acc, walker) do
    {new_obj, acc} = walker.(obj, acc)
    {{:property_access, [new_obj, prop]}, acc}
  end

  defp walk_children({:bracket_access, [obj, key]}, acc, walker) do
    {new_obj, acc} = walker.(obj, acc)
    {new_key, acc} = walker.(key, acc)
    {{:bracket_access, [new_obj, new_key]}, acc}
  end

  defp walk_children({:ternary, [c, t, f]}, acc, walker) do
    {new_c, acc} = walker.(c, acc)
    {new_t, acc} = walker.(t, acc)
    {new_f, acc} = walker.(f, acc)
    {{:ternary, [new_c, new_t, new_f]}, acc}
  end

  defp walk_children({:binary_op, [op, l, r]}, acc, walker) do
    {new_l, acc} = walker.(l, acc)
    {new_r, acc} = walker.(r, acc)
    {{:binary_op, [op, new_l, new_r]}, acc}
  end

  defp walk_children({:unary, [op_tag, expr]}, acc, walker) do
    {new_expr, acc} = walker.(expr, acc)
    {{:unary, [op_tag, new_expr]}, acc}
  end

  defp walk_children({:function_call, [head | args]}, acc, walker) do
    {new_args, acc} = Enum.map_reduce(args, acc, walker)
    {{:function_call, [head | new_args]}, acc}
  end

  defp walk_children(leaf, acc, _walker), do: {leaf, acc}
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/ast.ex test/ex_jexl/ast_test.exs
git commit -m "feat(ast): add ExJexl.AST module with prewalk/3"
```

---

## Task 12: Add `postwalk/3` and `walk/3` to `ExJexl.AST`

**Files:**
- Modify: `lib/ex_jexl/ast.ex`
- Modify: `test/ex_jexl/ast_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/ex_jexl/ast_test.exs` (before the final `end`):

```elixir
  describe "postwalk/3" do
    test "visits children before parent" do
      {:ok, ast} = Parser.parse("a + b")
      {_, acc} = AST.postwalk(ast, [], fn node, a -> {node, [node | a]} end)
      # In post-order, the binary_op comes last (deepest first).
      # Reverse acc to get visit order:
      visit_order = Enum.reverse(acc)
      [first | _] = visit_order
      assert first == {:identifier, "a"}
      [last | _] = acc  # acc is reverse of visit order, so first elem = last visited
      assert match?({:binary_op, _}, last)
    end

    test "transforms bottom-up" do
      {:ok, ast} = Parser.parse("x + 1")
      {new_ast, _} = AST.postwalk(ast, nil, fn
        {:integer, n}, a -> {{:integer, n * 10}, a}
        node, a -> {node, a}
      end)
      assert match?({:binary_op, [:+, {:identifier, "x"}, {:integer, 10}]}, new_ast)
    end
  end

  describe "walk/3 (read-only fold)" do
    test "collects all identifiers" do
      {:ok, ast} = Parser.parse("a + b * c")
      ids =
        AST.walk(ast, [], fn
          {:identifier, name}, acc -> [name | acc]
          _, acc -> acc
        end)
      assert Enum.sort(ids) == ["a", "b", "c"]
    end

    test "counts integer literals" do
      {:ok, ast} = Parser.parse("[1, 2, 3]")
      count =
        AST.walk(ast, 0, fn
          {:integer, _}, acc -> acc + 1
          _, acc -> acc
        end)
      assert count == 3
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: tests fail with "ExJexl.AST.postwalk/3 is undefined" and "ExJexl.AST.walk/3 is undefined".

- [ ] **Step 3: Add postwalk/3 and walk/3 to ExJexl.AST**

In `lib/ex_jexl/ast.ex`, just below the `prewalk/3` function definition, add:

```elixir
  @doc """
  Walks the AST in post-order, applying `fun` to each node and threading `acc`.

  Children are visited before their parent. Useful for bottom-up transformations.
  """
  @spec postwalk(ast, acc, (ast, acc -> {ast, acc})) :: {ast, acc} when acc: any
  def postwalk(ast, acc, fun) do
    {new_ast, new_acc} = walk_children(ast, acc, &postwalk(&1, &2, fun))
    fun.(new_ast, new_acc)
  end

  @doc """
  Read-only fold over the AST in pre-order.

  `fun` receives `(node, acc)` and returns the new accumulator. Equivalent
  to `prewalk/3` with the node passed through unchanged.
  """
  @spec walk(ast, acc, (ast, acc -> acc)) :: acc when acc: any
  def walk(ast, acc, fun) do
    {_, final} = prewalk(ast, acc, fn n, a -> {n, fun.(n, a)} end)
    final
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/ast.ex test/ex_jexl/ast_test.exs
git commit -m "feat(ast): add postwalk/3 and walk/3 helpers"
```

---

## Task 13: Add `find_transforms/2` to `ExJexl.AST`

**Files:**
- Modify: `lib/ex_jexl/ast.ex`
- Modify: `test/ex_jexl/ast_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/ex_jexl/ast_test.exs` (before the final `end`):

```elixir
  describe "find_transforms/2" do
    test "finds single transform with no args" do
      {:ok, ast} = Parser.parse("x|length")
      assert [match] = AST.find_transforms(ast, "length")
      assert match.name == "length"
      assert match.subject == {:identifier, "x"}
      assert match.args == []
    end

    test "finds transform with args" do
      {:ok, ast} = Parser.parse("'q'|answer('default')")
      assert [match] = AST.find_transforms(ast, "answer")
      assert match.name == "answer"
      assert match.subject == {:string, "q"}
      assert match.args == [{:string, "default"}]
    end

    test "finds chained transforms" do
      {:ok, ast} = Parser.parse("a|x|y")
      matches = AST.find_transforms(ast, :any)
      names = Enum.map(matches, & &1.name)
      assert "x" in names
      assert "y" in names
      assert length(matches) == 2
    end

    test "subject of outer chain transform is inner pipe" do
      {:ok, ast} = Parser.parse("a|x|y")
      [_x_match, y_match] = AST.find_transforms(ast, :any) |> Enum.sort_by(& &1.name)
      assert match?({:binary_op, [:|, _, _]}, y_match.subject)
    end

    test "any filter returns all transforms" do
      {:ok, ast} = Parser.parse("a|x|y|z")
      assert AST.find_transforms(ast, :any) |> length() == 3
    end

    test "string filter returns only matching name" do
      {:ok, ast} = Parser.parse("a|x|y|x")
      matches = AST.find_transforms(ast, "x")
      assert length(matches) == 2
      assert Enum.all?(matches, &(&1.name == "x"))
    end

    test "list filter returns matching names" do
      {:ok, ast} = Parser.parse("a|x|y|z")
      matches = AST.find_transforms(ast, ["x", "z"])
      names = Enum.map(matches, & &1.name) |> Enum.sort()
      assert names == ["x", "z"]
    end

    test "no match returns empty list" do
      {:ok, ast} = Parser.parse("a|x")
      assert [] == AST.find_transforms(ast, "missing")
    end

    test "expression with no transforms" do
      {:ok, ast} = Parser.parse("a + b")
      assert [] == AST.find_transforms(ast, :any)
    end

    test "transform inside ternary is found" do
      {:ok, ast} = Parser.parse("c ? a|x : b|y")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["x", "y"]
    end

    test "transform inside array is found" do
      {:ok, ast} = Parser.parse("[a|x, b|y]")
      names = AST.find_transforms(ast, :any) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["x", "y"]
    end

    test "transform inside function call is found" do
      {:ok, ast} = Parser.parse("f(a|x)")
      assert [match] = AST.find_transforms(ast, :any)
      assert match.name == "x"
    end

    test "default name filter is :any" do
      {:ok, ast} = Parser.parse("a|x|y")
      assert AST.find_transforms(ast) |> length() == 2
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: tests fail with "ExJexl.AST.find_transforms/1 is undefined".

- [ ] **Step 3: Add find_transforms/2 to ExJexl.AST**

In `lib/ex_jexl/ast.ex`, after the `walk/3` function and before `walk_children/3`, add:

```elixir
  @doc """
  Find all transform applications in the AST.

  Returns a list of matches, one per transform call:

      %{name: String.t(), subject: ast, args: [ast]}

  The `name` filter accepts:
    * `:any` — every transform call (default)
    * `String.t()` — exact name match
    * `[String.t()]` — any name in the list

  Chained pipes (`a|x|y`) yield one match per transform; the subject of an
  outer transform is the inner pipe AST.
  """
  @spec find_transforms(ast, :any | String.t() | [String.t()]) :: [%{
          name: String.t(),
          subject: ast,
          args: [ast]
        }]
  def find_transforms(ast, name \\ :any)

  def find_transforms(ast, :any) do
    ast
    |> walk([], fn
      {:binary_op, [:|, subject, transform_call]}, acc ->
        case extract_transform_call(transform_call) do
          {:ok, n, args} -> [%{name: n, subject: subject, args: args} | acc]
          :error -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  def find_transforms(ast, name) when is_binary(name) do
    find_transforms(ast, [name])
  end

  def find_transforms(ast, names) when is_list(names) do
    ast
    |> find_transforms(:any)
    |> Enum.filter(fn %{name: n} -> n in names end)
  end

  defp extract_transform_call({:identifier, name}), do: {:ok, name, []}

  defp extract_transform_call({:function_call, [{:identifier, name} | args]}),
    do: {:ok, name, args}

  defp extract_transform_call(_), do: :error
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl/ast_test.exs`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/ast.ex test/ex_jexl/ast_test.exs
git commit -m "feat(ast): add find_transforms/2 helper"
```

---

## Task 14: Create `ExJexl.Validator` module

**Files:**
- Create: `lib/ex_jexl/validator.ex`
- Create: `test/ex_jexl/validator_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/ex_jexl/validator_test.exs`:

```elixir
defmodule ExJexl.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExJexl.Validator

  describe "validate/2" do
    test "no validators returns ok with empty errors" do
      assert {:ok, []} = Validator.validate("1 + 1")
    end

    test "parse failure returns error tuple" do
      assert {:error, _reason} = Validator.validate("1 + + 2")
    end

    test "single validator with no errors" do
      validator = fn _ast -> [] end
      assert {:ok, []} = Validator.validate("1 + 1", [validator])
    end

    test "single validator with errors" do
      validator = fn _ast -> ["always wrong"] end
      assert {:ok, ["always wrong"]} = Validator.validate("1 + 1", [validator])
    end

    test "multiple validators concat errors" do
      v1 = fn _ -> ["e1"] end
      v2 = fn _ -> ["e2", "e3"] end
      assert {:ok, ["e1", "e2", "e3"]} = Validator.validate("1 + 1", [v1, v2])
    end

    test "validator can use AST.find_transforms to inspect expression" do
      validator = fn ast ->
        ast
        |> ExJexl.AST.find_transforms("answer")
        |> Enum.reject(fn %{subject: subject} -> match?({:string, _}, subject) end)
        |> Enum.map(fn _ -> "answer subject must be a string slug" end)
      end

      # Valid: subject is string
      assert {:ok, []} = Validator.validate("'q'|answer", [validator])

      # Invalid: subject is identifier
      assert {:ok, ["answer subject must be a string slug"]} =
               Validator.validate("x|answer", [validator])
    end
  end

  describe "validate_ast/2" do
    test "runs validators against parsed AST" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      assert [] == Validator.validate_ast(ast, [])
    end

    test "no validators returns empty list" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      assert [] == Validator.validate_ast(ast)
    end

    test "collects errors from all validators" do
      {:ok, ast} = ExJexl.Parser.parse("1 + 1")
      v1 = fn _ -> ["a"] end
      v2 = fn _ -> ["b"] end
      assert ["a", "b"] == Validator.validate_ast(ast, [v1, v2])
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl/validator_test.exs`
Expected: tests fail with "ExJexl.Validator.validate/1 is undefined".

- [ ] **Step 3: Implement ExJexl.Validator**

Create `lib/ex_jexl/validator.ex`:

```elixir
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ex_jexl/validator_test.exs`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl/validator.ex test/ex_jexl/validator_test.exs
git commit -m "feat(validator): add pluggable validator API"
```

---

## Task 15: Extend `use ExJexl` with `validators:` option

**Files:**
- Modify: `lib/ex_jexl.ex`
- Modify: `test/ex_jexl_test.exs`

- [ ] **Step 1: Write failing tests**

Add a new describe block to `test/ex_jexl_test.exs` (place it after the existing `describe "use ExJexl"` block — search for that and add directly below):

```elixir
  describe "use ExJexl with validators" do
    defmodule ValidatorJexl do
      use ExJexl,
        validators: [
          fn _ast -> ["module-level error"] end
        ]
    end

    test "validate/1 uses module-level validators" do
      assert {:ok, ["module-level error"]} = ValidatorJexl.validate("1 + 1")
    end

    test "parse error returns {:error, _}" do
      assert {:error, _} = ValidatorJexl.validate("1 + + 2")
    end

    test "validate/2 merges per-call validators after module-level" do
      extra = fn _ast -> ["per-call error"] end

      assert {:ok, ["module-level error", "per-call error"]} =
               ValidatorJexl.validate("1 + 1", validators: [extra])
    end

    test "no module-level validators works when use ExJexl omits the opt" do
      defmodule NoValidatorsJexl do
        use ExJexl, transforms: %{}
      end

      assert {:ok, []} = NoValidatorsJexl.validate("1 + 1")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ex_jexl_test.exs`
Expected: tests fail with "ValidatorJexl.validate/1 is undefined".

- [ ] **Step 3: Extend the __using__ macro**

In `lib/ex_jexl.ex`, replace the `defmacro __using__(opts)` block with:

```elixir
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ex_jexl.ex test/ex_jexl_test.exs
git commit -m "feat: use ExJexl accepts :validators option"
```

---

## Task 16: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add new version entry**

Open `CHANGELOG.md` and add a new section directly below the line `and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).`:

```markdown
## [Unreleased]

### Breaking changes
- Built-in transform error semantics now match Caluma pyjexl: nil-on-error rather than raising or returning `0`.
  - `length` on numbers/booleans/nil now returns `nil` (was `0`).
  - `first`/`last` on non-list now return `nil` (previously raised).
  - `abs` on non-number now returns `nil` (previously raised).
- `floor`/`ceil` are now correct for negative numbers (use `:math.floor` / `:math.ceil` rather than `trunc`).
- `round` is now half-up (matches Caluma / JS `Math.round`), not half-to-even (banker's). Always returns float. Accepts an optional decimal-places argument: `n|round(2)`.
- Elixir `~> 1.18` / OTP 27+ required (uses stdlib `:json`).

### Added
- New built-in transforms: `mapby`, `stringify`, `min`, `max`, `sum`, `avg`, `debug`.
- `ExJexl.AST` module — `prewalk/3`, `postwalk/3`, `walk/3`, `find_transforms/2` for downstream analyzers and dependency extraction.
- `ExJexl.Validator` module — pluggable validator API. `validate/2` and `validate_ast/2`. Zero default validators; host applications register their own.
- `use ExJexl` accepts a `validators: [...]` option; module-level validators merge with per-call ones.
- Documented public AST format in `ExJexl.AST` module documentation.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for Caluma JEXL parity"
```

---

## Task 17: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update built-in transforms list and add new docs**

Replace the line in `README.md` that reads:

```
Available built-in transforms: `length`, `first`, `last`, `reverse`, `sort`, `unique`, `flatten`, `join`, `upper`, `lower`, `trim`, `split`, `keys`, `values`, `type`.
```

with:

```
Available built-in transforms: `length`, `first`, `last`, `reverse`, `sort`, `unique`, `flatten`, `join`, `mapby`, `stringify`, `upper`, `lower`, `trim`, `split`, `keys`, `values`, `abs`, `round`, `floor`, `ceil`, `min`, `max`, `sum`, `avg`, `debug`, `type`, `not`.

Note: most built-ins return `nil` for type-mismatched inputs (e.g. `42|length`, `"hello"|first`) rather than raising — matching Caluma's pyjexl semantics.
```

Then **append** the following new sections to the end of `README.md`, before the `## License` section:

```markdown
## Caluma compatibility

`ex_jexl` aims to be a drop-in replacement for the JEXL evaluator inside
[projectcaluma/caluma](https://github.com/projectcaluma/caluma) (`caluma_core/jexl.py`).
Built-in transforms, error semantics (nil-on-error), and operator
precedence (`intersects`) all match Caluma's pyjexl.

What's intentionally **out of scope**:

- Domain-specific transforms (`answer`, `task`, `tasks`, `groups`). Register
  these as custom transforms in your application — see the
  [Custom Transforms and Functions](#custom-transforms-and-functions) section.
- Parsed-AST cache. If you need one, wrap `ExJexl.Parser.parse/1` with
  your own caching layer (e.g. `:persistent_term`, `Cachex`, ETS).
- Caluma's `_expr_stack` feature for `debug` (logging the surrounding
  expression). `debug` here logs only the value (and optional label).

## Analyzing expressions

`ExJexl.AST` exposes the parsed AST for inspection — useful for dependency
extraction, custom analyzers, etc.

```elixir
{:ok, ast} = ExJexl.Parser.parse("'q1'|answer + 'q2'|answer")

# Find all transforms by name
ExJexl.AST.find_transforms(ast, "answer")
# => [
#   %{name: "answer", subject: {:string, "q1"}, args: []},
#   %{name: "answer", subject: {:string, "q2"}, args: []}
# ]

# Read-only fold to collect all identifiers
ExJexl.AST.walk(ast, [], fn
  {:identifier, name}, acc -> [name | acc]
  _, acc -> acc
end)
```

The AST format is documented in the `ExJexl.AST` module documentation.
Walkers `prewalk/3` and `postwalk/3` mirror `Macro.prewalk/postwalk` for
node-rewriting use cases.

## Validation

`ExJexl.Validator` runs a list of validator functions over a parsed
expression and returns all errors at once.

```elixir
# Validator that requires `answer` transform subjects to be string literals
answer_validator = fn ast ->
  ast
  |> ExJexl.AST.find_transforms("answer")
  |> Enum.reject(fn %{subject: subject} -> match?({:string, _}, subject) end)
  |> Enum.map(fn _ -> "answer subject must be a string slug" end)
end

ExJexl.Validator.validate("'q'|answer", [answer_validator])
# => {:ok, []}

ExJexl.Validator.validate("x|answer", [answer_validator])
# => {:ok, ["answer subject must be a string slug"]}

ExJexl.Validator.validate("1 + + 2", [answer_validator])
# => {:error, "expected ..."}  # parse failure short-circuits
```

For application-level validators, pass them to `use ExJexl`:

```elixir
defmodule MyApp.Jexl do
  use ExJexl,
    transforms: %{...},
    validators: [
      &MyApp.Jexl.Validators.answer/1,
      &MyApp.Jexl.Validators.task/1
    ]
end

MyApp.Jexl.validate(expr)
# uses module-level validators

MyApp.Jexl.validate(expr, validators: [&extra_validator/1])
# merges: module-level ++ per-call extras
```
```

- [ ] **Step 2: Add OTP 27+ note to Installation**

In `README.md`, find the `## Installation` section. Below the `mix.exs` deps snippet, add this paragraph:

```markdown
**Requirements:** Elixir `~> 1.18` and OTP 27+ (the `stringify` transform uses the stdlib `:json` module).
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document Caluma compat, AST module, validators"
```

---

## Self-review

After all tasks complete, verify:

1. **Spec coverage:**
   - mapby ✓ (Task 2) · stringify ✓ (Task 3) · min/max/sum/avg ✓ (Task 4) · debug ✓ (Task 5)
   - length nil ✓ (Task 6) · first/last nil ✓ (Task 7) · abs nil ✓ (Task 8)
   - floor/ceil ✓ (Task 9) · round half-up ✓ (Task 10)
   - AST module: prewalk ✓ (Task 11) · postwalk + walk ✓ (Task 12) · find_transforms ✓ (Task 13)
   - Validator module ✓ (Task 14) · `use ExJexl :validators` ✓ (Task 15)
   - mix.exs bump ✓ (Task 1) · CHANGELOG ✓ (Task 16) · README ✓ (Task 17)
   - No tasks needed for: AST format docs (covered by Task 11 module doc), zero default validators (covered by Task 14 — empty default), no new deps (Task 1 confirms `:json` stdlib is enough).

2. **Final test run:**

```bash
mix test
```

Expected: all tests pass, no regressions.

3. **Final manual verification:**

```bash
# Confirm new transforms work end-to-end
mix run -e 'IO.inspect ExJexl.eval("[1,2,3,4,5]|avg")'
# => {:ok, 3.0}

mix run -e 'IO.inspect ExJexl.eval("nums|stringify", %{"nums" => [1,2,3]})'
# => {:ok, "[1,2,3]"}

mix run -e 'IO.inspect ExJexl.eval("x|round(2)", %{"x" => 1.235})'
# => {:ok, 1.24}
```
