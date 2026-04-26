defmodule TestJexl do
  use ExJexl,
    transforms: %{
      "double" => fn val -> val * 2 end,
      "upcase" => &String.upcase/1,
      "with_greeting" => fn val, ctx -> "#{ctx["greeting"]} #{val}" end
    },
    functions: %{
      "add" => fn [a, b] -> a + b end
    }
end

defmodule ExJexlTest do
  use ExUnit.Case
  doctest ExJexl

  describe "basic literals" do
    test "evaluates integers" do
      assert ExJexl.eval("42") == {:ok, 42}
      assert ExJexl.eval("-17") == {:ok, -17}
      assert ExJexl.eval("0") == {:ok, 0}
    end

    test "evaluates floats" do
      assert ExJexl.eval("3.14") == {:ok, 3.14}
      assert ExJexl.eval("-2.5") == {:ok, -2.5}
    end

    test "evaluates strings" do
      assert ExJexl.eval(~s("hello")) == {:ok, "hello"}
      assert ExJexl.eval("'world'") == {:ok, "world"}
      assert ExJexl.eval(~s("")) == {:ok, ""}
    end

    test "evaluates booleans" do
      assert ExJexl.eval("true") == {:ok, true}
      assert ExJexl.eval("false") == {:ok, false}
    end

    test "evaluates null" do
      assert ExJexl.eval("null") == {:ok, nil}
    end
  end

  describe "identifiers and context" do
    test "evaluates identifiers from context" do
      context = %{"name" => "Alice", "age" => 30}
      assert ExJexl.eval("name", context) == {:ok, "Alice"}
      assert ExJexl.eval("age", context) == {:ok, 30}
    end

    test "returns nil for missing identifiers" do
      assert ExJexl.eval("missing") == {:ok, nil}
    end

    test "works with atom keys" do
      context = %{name: "Bob", age: 25}
      assert ExJexl.eval("name", context) == {:ok, "Bob"}
      assert ExJexl.eval("age", context) == {:ok, 25}
    end
  end

  describe "arithmetic operations" do
    test "addition" do
      assert ExJexl.eval("5 + 3") == {:ok, 8}
      assert ExJexl.eval("1.5 + 2.5") == {:ok, 4.0}
    end

    test "subtraction" do
      assert ExJexl.eval("10 - 4") == {:ok, 6}
      assert ExJexl.eval("3.5 - 1.2") == {:ok, 2.3}
    end

    test "multiplication" do
      assert ExJexl.eval("6 * 7") == {:ok, 42}
      assert ExJexl.eval("2.5 * 4") == {:ok, 10.0}
    end

    test "division" do
      assert ExJexl.eval("15 / 3") == {:ok, 5.0}
      assert ExJexl.eval("10 / 4") == {:ok, 2.5}
    end

    test "modulo" do
      assert ExJexl.eval("17 % 5") == {:ok, 2}
      assert ExJexl.eval("10 % 3") == {:ok, 1}
    end

    test "operator precedence" do
      assert ExJexl.eval("2 + 3 * 4") == {:ok, 14}
      assert ExJexl.eval("(2 + 3) * 4") == {:ok, 20}
    end
  end

  describe "comparison operations" do
    test "equality" do
      assert ExJexl.eval("5 == 5") == {:ok, true}
      assert ExJexl.eval("5 == 3") == {:ok, false}
      assert ExJexl.eval("5 != 3") == {:ok, true}
      assert ExJexl.eval("5 != 5") == {:ok, false}
    end

    test "relational operators" do
      assert ExJexl.eval("5 > 3") == {:ok, true}
      assert ExJexl.eval("3 > 5") == {:ok, false}
      assert ExJexl.eval("5 >= 5") == {:ok, true}
      assert ExJexl.eval("3 < 5") == {:ok, true}
      assert ExJexl.eval("5 <= 5") == {:ok, true}
    end

    test "string comparison" do
      assert ExJexl.eval(~s("apple" < "banana")) == {:ok, true}
      assert ExJexl.eval(~s("zebra" > "apple")) == {:ok, true}
    end
  end

  describe "logical operations" do
    test "logical AND" do
      assert ExJexl.eval("true && true") == {:ok, true}
      assert ExJexl.eval("true && false") == {:ok, false}
      assert ExJexl.eval("false && true") == {:ok, false}
    end

    test "logical OR" do
      assert ExJexl.eval("true || false") == {:ok, true}
      assert ExJexl.eval("false || true") == {:ok, true}
      assert ExJexl.eval("false || false") == {:ok, false}
    end

    test "logical NOT" do
      assert ExJexl.eval("!true") == {:ok, false}
      assert ExJexl.eval("!false") == {:ok, true}
      assert ExJexl.eval("!0") == {:ok, true}
      assert ExJexl.eval("!1") == {:ok, false}
    end

    test "short-circuit evaluation" do
      context = %{"x" => 5}
      assert ExJexl.eval("false && x", context) == {:ok, false}
      assert ExJexl.eval("true || x", context) == {:ok, true}
    end
  end

  describe "property access" do
    test "dot notation" do
      context = %{"user" => %{"name" => "Alice", "age" => 30}}
      assert ExJexl.eval("user.name", context) == {:ok, "Alice"}
      assert ExJexl.eval("user.age", context) == {:ok, 30}
    end

    test "bracket notation" do
      context = %{"user" => %{"name" => "Bob"}, "key" => "name"}
      assert ExJexl.eval("user[key]", context) == {:ok, "Bob"}
      assert ExJexl.eval(~s(user["name"]), context) == {:ok, "Bob"}
    end

    test "array access" do
      context = %{"items" => [10, 20, 30]}
      assert ExJexl.eval("items[0]", context) == {:ok, 10}
      assert ExJexl.eval("items[1]", context) == {:ok, 20}
      assert ExJexl.eval("items[2]", context) == {:ok, 30}
    end

    test "nested property access" do
      context = %{
        "data" => %{
          "users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]
        }
      }

      assert ExJexl.eval("data.users[0].name", context) == {:ok, "Alice"}
      assert ExJexl.eval("data.users[1].name", context) == {:ok, "Bob"}
    end
  end

  describe "arrays" do
    test "array literals" do
      assert ExJexl.eval("[1, 2, 3]") == {:ok, [1, 2, 3]}
      assert ExJexl.eval("[]") == {:ok, []}
      assert ExJexl.eval(~s(["a", "b", "c"])) == {:ok, ["a", "b", "c"]}
    end

    test "mixed arrays" do
      assert ExJexl.eval(~s([1, "hello", true, null])) == {:ok, [1, "hello", true, nil]}
    end

    test "nested arrays" do
      assert ExJexl.eval("[[1, 2], [3, 4]]") == {:ok, [[1, 2], [3, 4]]}
    end
  end

  describe "objects" do
    test "object literals" do
      result = ExJexl.eval(~s({"name": "Alice", "age": 30}))
      assert result == {:ok, %{"name" => "Alice", "age" => 30}}
    end

    test "empty objects" do
      assert ExJexl.eval("{}") == {:ok, %{}}
    end

    test "nested objects" do
      result = ExJexl.eval(~s({"user": {"name": "Bob", "active": true}}))
      expected = %{"user" => %{"name" => "Bob", "active" => true}}
      assert result == {:ok, expected}
    end
  end

  describe "built-in functions" do
    test "length function" do
      context = %{"items" => [1, 2, 3], "text" => "hello"}
      assert ExJexl.eval("length(items)", context) == {:ok, 3}
      assert ExJexl.eval("length(text)", context) == {:ok, 5}
    end

    test "keys function" do
      context = %{"obj" => %{"a" => 1, "b" => 2}}
      {:ok, keys} = ExJexl.eval("keys(obj)", context)
      assert Enum.sort(keys) == ["a", "b"]
    end

    test "values function" do
      context = %{"obj" => %{"a" => 1, "b" => 2}}
      {:ok, values} = ExJexl.eval("values(obj)", context)
      assert Enum.sort(values) == [1, 2]
    end

    test "type function" do
      assert ExJexl.eval("type(42)") == {:ok, "number"}
      assert ExJexl.eval(~s{type("hello")}) == {:ok, "string"}
      assert ExJexl.eval("type(true)") == {:ok, "boolean"}
      assert ExJexl.eval("type(null)") == {:ok, "null"}
      assert ExJexl.eval("type([])") == {:ok, "array"}
      assert ExJexl.eval("type({})") == {:ok, "object"}
    end
  end

  describe "transforms" do
    test "length transform" do
      context = %{"items" => [1, 2, 3, 4]}
      assert ExJexl.eval("items|length", context) == {:ok, 4}
    end

    test "string transforms" do
      context = %{"text" => "Hello World"}
      assert ExJexl.eval("text|upper", context) == {:ok, "HELLO WORLD"}
      assert ExJexl.eval("text|lower", context) == {:ok, "hello world"}
    end

    test "array transforms" do
      context = %{"numbers" => [3, 1, 4, 1, 5]}
      assert ExJexl.eval("numbers|first", context) == {:ok, 3}
      assert ExJexl.eval("numbers|last", context) == {:ok, 5}
      assert ExJexl.eval("numbers|reverse", context) == {:ok, [5, 1, 4, 1, 3]}
      assert ExJexl.eval("numbers|sort", context) == {:ok, [1, 1, 3, 4, 5]}
      assert ExJexl.eval("numbers|unique", context) == {:ok, [3, 1, 4, 5]}
    end

    test "chained transforms" do
      context = %{"items" => [1, 2, 3, 4, 5]}
      assert ExJexl.eval("items|reverse|first", context) == {:ok, 5}
    end

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

    test "stringify on map produces compact JSON" do
      ctx = %{"obj" => %{"a" => 1, "b" => "two"}}
      assert {:ok, json} = ExJexl.eval("obj|stringify", ctx)
      refute json =~ " "
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

    test "stringify with nested nil values" do
      ctx = %{"obj" => %{"a" => nil, "b" => [1, nil, 3]}}
      assert {:ok, ~s({"a":null,"b":[1,null,3]})} = ExJexl.eval("obj|stringify", ctx)
    end

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

    test "length on number returns nil (was 0)" do
      assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => 42})
    end

    test "length on nil returns nil" do
      assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => nil})
    end

    test "length on boolean returns nil" do
      assert {:ok, nil} = ExJexl.eval("x|length", %{"x" => true})
    end

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
  end

  describe "membership operator" do
    test "in operator with arrays" do
      context = %{"items" => [1, 2, 3]}
      assert ExJexl.eval("2 in items", context) == {:ok, true}
      assert ExJexl.eval("5 in items", context) == {:ok, false}
    end

    test "in operator with objects" do
      context = %{"obj" => %{"name" => "Alice", "age" => 30}}
      assert ExJexl.eval(~s("name" in obj), context) == {:ok, true}
      assert ExJexl.eval(~s("email" in obj), context) == {:ok, false}
    end

    test "in operator with strings" do
      context = %{"text" => "hello world"}
      assert ExJexl.eval(~s("world" in text), context) == {:ok, true}
      assert ExJexl.eval(~s("goodbye" in text), context) == {:ok, false}
    end
  end

  describe "complex expressions" do
    test "conditional logic" do
      context = %{"age" => 25}
      assert ExJexl.eval("age >= 18 && age < 65", context) == {:ok, true}
      assert ExJexl.eval("age < 18 || age >= 65", context) == {:ok, false}
    end

    test "mixed operations" do
      context = %{"price" => 100, "discount" => 0.1, "tax" => 0.08}
      assert ExJexl.eval("price * (1 - discount) * (1 + tax)", context) == {:ok, 97.2}
    end

    test "string concatenation" do
      context = %{"first" => "John", "last" => "Doe"}
      assert ExJexl.eval(~s(first + " " + last), context) == {:ok, "John Doe"}
    end
  end

  describe "custom functions" do
    test "custom function with single arg" do
      opts = [functions: %{"double" => fn [x] -> x * 2 end}]
      assert ExJexl.eval("double(5)", %{}, opts) == {:ok, 10}
    end

    test "custom function with multiple args" do
      opts = [functions: %{"add" => fn [a, b] -> a + b end}]
      assert ExJexl.eval("add(1, 2)", %{}, opts) == {:ok, 3}
    end

    test "custom function with context" do
      opts = [functions: %{"greet" => fn [name] -> "Hello, #{name}!" end}]
      context = %{"name" => "Alice"}
      assert ExJexl.eval("greet(name)", context, opts) == {:ok, "Hello, Alice!"}
    end

    test "custom function overrides built-in" do
      opts = [functions: %{"length" => fn [_] -> 999 end}]
      assert ExJexl.eval("length([1,2,3])", %{}, opts) == {:ok, 999}
    end

    test "falls back to built-in when no custom function" do
      assert ExJexl.eval("length([1,2,3])", %{}, []) == {:ok, 3}
    end
  end

  describe "custom transforms" do
    test "custom transform" do
      opts = [transforms: %{"double" => fn val -> val * 2 end}]
      assert ExJexl.eval("value|double", %{"value" => 5}, opts) == {:ok, 10}
    end

    test "custom transform with context (arity 2)" do
      opts = [transforms: %{"greet" => fn val, ctx -> "#{ctx["greeting"]} #{val}" end}]
      context = %{"name" => "Alice", "greeting" => "Hello"}
      assert ExJexl.eval("name|greet", context, opts) == {:ok, "Hello Alice"}
    end

    test "custom transform in chain" do
      opts = [transforms: %{"double" => fn val -> val * 2 end}]
      context = %{"items" => [1, 2, 3]}
      assert ExJexl.eval("items|first|double", context, opts) == {:ok, 2}
    end

    test "custom transform overrides built-in" do
      opts = [transforms: %{"upper" => fn _ -> "CUSTOM" end}]
      assert ExJexl.eval("text|upper", %{"text" => "hello"}, opts) == {:ok, "CUSTOM"}
    end

    test "falls back to built-in when no custom transform" do
      assert ExJexl.eval("text|upper", %{"text" => "hello"}, []) == {:ok, "HELLO"}
    end

    test "custom transform with arguments" do
      opts = [transforms: %{"append" => fn val, args, _ctx -> val <> Enum.join(args, "") end}]
      assert ExJexl.eval("name|append('!')", %{"name" => "hello"}, opts) == {:ok, "hello!"}
    end

    test "custom transform with multiple arguments" do
      opts = [transforms: %{"between" => fn val, [lo, hi], _ctx -> val >= lo && val <= hi end}]
      assert ExJexl.eval("age|between(18, 65)", %{"age" => 25}, opts) == {:ok, true}
    end

    test "transform with no args still works with arity-3 function" do
      opts = [transforms: %{"double" => fn val, _args, _ctx -> val * 2 end}]
      assert ExJexl.eval("x|double", %{"x" => 5}, opts) == {:ok, 10}
    end
  end

  describe "ternary expressions" do
    test "true condition" do
      assert ExJexl.eval("true ? 1 : 2") == {:ok, 1}
    end

    test "false condition" do
      assert ExJexl.eval("false ? 1 : 2") == {:ok, 2}
    end

    test "with context" do
      context = %{"age" => 25}
      assert ExJexl.eval("age >= 18 ? 'adult' : 'minor'", context) == {:ok, "adult"}
    end

    test "with context - false branch" do
      context = %{"age" => 12}
      assert ExJexl.eval("age >= 18 ? 'adult' : 'minor'", context) == {:ok, "minor"}
    end

    test "nested ternary" do
      context = %{"score" => 85}

      assert ExJexl.eval("score >= 90 ? 'A' : score >= 80 ? 'B' : 'C'", context) ==
               {:ok, "B"}
    end

    test "ternary with expressions in branches" do
      context = %{"x" => 10}
      assert ExJexl.eval("x > 5 ? x * 2 : x + 1", context) == {:ok, 20}
    end

    test "truthy/falsy values" do
      assert ExJexl.eval("0 ? 'yes' : 'no'") == {:ok, "no"}
      assert ExJexl.eval("1 ? 'yes' : 'no'") == {:ok, "yes"}
      assert ExJexl.eval("null ? 'yes' : 'no'") == {:ok, "no"}
    end
  end

  describe "use ExJexl wrapper module" do
    test "default transforms work without opts" do
      assert TestJexl.eval("value|double", %{"value" => 5}) == {:ok, 10}
    end

    test "default functions work without opts" do
      assert TestJexl.eval("add(2, 3)") == {:ok, 5}
    end

    test "default transform with context (arity 2)" do
      context = %{"name" => "World", "greeting" => "Hello"}
      assert TestJexl.eval("name|with_greeting", context) == {:ok, "Hello World"}
    end

    test "per-call opts override defaults" do
      opts = [transforms: %{"double" => fn val -> val * 3 end}]
      assert TestJexl.eval("value|double", %{"value" => 5}, opts) == {:ok, 15}
    end

    test "per-call opts merge with defaults" do
      opts = [transforms: %{"triple" => fn val -> val * 3 end}]
      context = %{"value" => 5}
      assert TestJexl.eval("value|double", context, opts) == {:ok, 10}
      assert TestJexl.eval("value|triple", context, opts) == {:ok, 15}
    end

    test "eval! works with defaults" do
      assert TestJexl.eval!("value|double", %{"value" => 5}) == 10
    end

    test "eval! raises on error" do
      assert_raise RuntimeError, fn ->
        TestJexl.eval!("10 / 0")
      end
    end
  end

  describe "intersects operator" do
    test "arrays with common elements" do
      ctx = %{"a" => [1, 2, 3], "b" => [2, 3, 4]}
      assert ExJexl.eval("a intersects b", ctx) == {:ok, true}
    end

    test "arrays with no common elements" do
      ctx = %{"a" => [1, 2], "b" => [3, 4]}
      assert ExJexl.eval("a intersects b", ctx) == {:ok, false}
    end

    test "empty array intersects nothing" do
      ctx = %{"a" => [], "b" => [1, 2]}
      assert ExJexl.eval("a intersects b", ctx) == {:ok, false}
    end

    test "intersects with inline arrays" do
      assert ExJexl.eval("[1, 2] intersects [2, 3]") == {:ok, true}
    end

    test "intersects with string arrays" do
      ctx = %{"tags" => ["red", "blue"], "filter" => ["blue", "green"]}
      assert ExJexl.eval("tags intersects filter", ctx) == {:ok, true}
    end

    test "intersects in compound expression" do
      ctx = %{"tags" => ["admin"], "required" => ["admin", "super"]}
      assert ExJexl.eval("tags intersects required && true", ctx) == {:ok, true}
    end
  end

  describe "error handling" do
    test "division by zero" do
      assert ExJexl.eval("10 / 0") == {:error, "Division by zero"}
    end

    test "modulo by zero" do
      assert ExJexl.eval("10 % 0") == {:error, "Modulo by zero"}
    end

    test "invalid syntax" do
      assert {:error, _} = ExJexl.eval("1 + + 2")
    end

    test "eval! raises on error" do
      assert_raise RuntimeError, fn ->
        ExJexl.eval!("10 / 0")
      end
    end
  end
end
