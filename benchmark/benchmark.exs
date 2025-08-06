defmodule ExJexlBenchmark do
  @moduledoc """
  Comprehensive benchmarks for ExJexl performance testing.
  
  Run with: mix run benchmark/benchmark.exs
  """
  
  # Sample contexts for benchmarking
  @simple_context %{
    "name" => "Alice",
    "age" => 30,
    "active" => true,
    "score" => 95.5
  }
  
  @complex_context %{
    "user" => %{
      "profile" => %{
        "name" => "John Doe",
        "email" => "john@example.com",
        "settings" => %{
          "theme" => "dark",
          "notifications" => true
        }
      },
      "stats" => %{
        "login_count" => 42,
        "last_login" => "2024-01-15"
      }
    },
    "data" => %{
      "items" => [1, 2, 3, 4, 5, 10, 20, 30],
      "users" => [
        %{"name" => "Alice", "age" => 25, "active" => true},
        %{"name" => "Bob", "age" => 30, "active" => false},
        %{"name" => "Charlie", "age" => 35, "active" => true}
      ],
      "config" => %{
        "max_items" => 100,
        "timeout" => 30.0,
        "features" => ["auth", "logging", "caching"]
      }
    },
    "metrics" => %{
      "response_times" => [12.5, 15.2, 8.9, 22.1, 11.3],
      "success_rate" => 0.95,
      "error_count" => 3
    }
  }
  
  @atom_context %{
    name: "Alice",
    age: 30,
    active: true,
    items: [1, 2, 3, 4, 5]
  }
  
  def run_benchmarks do
    IO.puts("🚀 Running ExJexl Performance Benchmarks")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Test different categories of expressions
    benchmark_literals()
    benchmark_arithmetic()
    benchmark_comparisons()
    benchmark_logical_operations()
    benchmark_property_access()
    benchmark_transforms()
    benchmark_complex_expressions()
    benchmark_parsing_vs_evaluation()
    benchmark_context_types()
    
    IO.puts("\n✅ Benchmarking completed!")
  end
  
  defp benchmark_literals do
    IO.puts("\n📊 Benchmarking Literals")
    
    Benchee.run(%{
      "integer" => fn -> ExJexl.eval("42") end,
      "float" => fn -> ExJexl.eval("3.14159") end,
      "string" => fn -> ExJexl.eval(~s("hello world")) end,
      "boolean_true" => fn -> ExJexl.eval("true") end,
      "boolean_false" => fn -> ExJexl.eval("false") end,
      "null" => fn -> ExJexl.eval("null") end,
      "array_small" => fn -> ExJexl.eval("[1, 2, 3]") end,
      "array_large" => fn -> ExJexl.eval("[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]") end,
      "object_small" => fn -> ExJexl.eval(~s({"name": "test", "value": 42})) end,
      "object_nested" => fn -> ExJexl.eval(~s({"user": {"name": "Alice", "age": 30}, "active": true})) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_arithmetic do
    IO.puts("\n🔢 Benchmarking Arithmetic Operations")
    
    Benchee.run(%{
      "simple_addition" => fn -> ExJexl.eval("2 + 3") end,
      "chain_addition" => fn -> ExJexl.eval("1 + 2 + 3 + 4 + 5") end,
      "mixed_arithmetic" => fn -> ExJexl.eval("10 * 5 + 3 - 8 / 2") end,
      "parentheses" => fn -> ExJexl.eval("(10 + 5) * (3 - 1)") end,
      "complex_math" => fn -> ExJexl.eval("((15 + 25) * 2 - 10) / (5 + 3)") end,
      "with_context" => fn -> ExJexl.eval("price * (1 - discount) * (1 + tax)", %{
        "price" => 100,
        "discount" => 0.1,
        "tax" => 0.08
      }) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_comparisons do
    IO.puts("\n⚖️ Benchmarking Comparison Operations")
    
    Benchee.run(%{
      "equality" => fn -> ExJexl.eval("5 == 5") end,
      "inequality" => fn -> ExJexl.eval("5 != 3") end,
      "greater_than" => fn -> ExJexl.eval("10 > 5") end,
      "less_than_equal" => fn -> ExJexl.eval("3 <= 5") end,
      "string_comparison" => fn -> ExJexl.eval(~s("apple" < "banana")) end,
      "with_context" => fn -> ExJexl.eval("age >= 18", @simple_context) end,
      "membership_array" => fn -> ExJexl.eval("2 in items", @atom_context) end,
      "membership_string" => fn -> ExJexl.eval(~s("world" in text), %{"text" => "hello world"}) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_logical_operations do
    IO.puts("\n🧠 Benchmarking Logical Operations")
    
    Benchee.run(%{
      "and_operation" => fn -> ExJexl.eval("true && false") end,
      "or_operation" => fn -> ExJexl.eval("false || true") end,
      "not_operation" => fn -> ExJexl.eval("!false") end,
      "complex_logic" => fn -> ExJexl.eval("(age >= 18 && active) || name == 'admin'", @simple_context) end,
      "short_circuit_and" => fn -> ExJexl.eval("false && expensive_operation", %{"expensive_operation" => true}) end,
      "short_circuit_or" => fn -> ExJexl.eval("true || expensive_operation", %{"expensive_operation" => false}) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_property_access do
    IO.puts("\n🔍 Benchmarking Property Access")
    
    Benchee.run(%{
      "simple_property" => fn -> ExJexl.eval("name", @simple_context) end,
      "dot_notation" => fn -> ExJexl.eval("user.profile.name", @complex_context) end,
      "bracket_notation" => fn -> ExJexl.eval(~s(user["profile"]["name"]), @complex_context) end,
      "array_access" => fn -> ExJexl.eval("data.items[0]", @complex_context) end,
      "nested_array_access" => fn -> ExJexl.eval("data.users[0].name", @complex_context) end,
      "deep_nesting" => fn -> ExJexl.eval("user.profile.settings.theme", @complex_context) end,
      "mixed_access" => fn -> ExJexl.eval("data.users[1][\"age\"]", @complex_context) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_transforms do
    IO.puts("\n🔄 Benchmarking Transforms")
    
    Benchee.run(%{
      "single_transform" => fn -> ExJexl.eval("items|length", @atom_context) end,
      "string_transform" => fn -> ExJexl.eval("name|upper", @simple_context) end,
      "array_transform" => fn -> ExJexl.eval("data.items|reverse", @complex_context) end,
      "chained_transforms" => fn -> ExJexl.eval("data.items|reverse|first", @complex_context) end,
      "multiple_chained" => fn -> ExJexl.eval("data.response_times|sort|reverse|first", 
        %{"data" => %{"response_times" => [12.5, 15.2, 8.9, 22.1, 11.3]}}) end,
      "complex_chain" => fn -> ExJexl.eval("metrics.response_times|sort|reverse|length", @complex_context) end
    }, time: 2, memory_time: 1)
  end
  
  defp benchmark_complex_expressions do
    IO.puts("\n🎯 Benchmarking Complex Expressions")
    
    Benchee.run(%{
      "conditional_logic" => fn -> 
        ExJexl.eval("user.profile.name != null && data.users|length > 0", @complex_context) 
      end,
      "mathematical_with_access" => fn -> 
        ExJexl.eval("(data.items|length * 10) + user.stats.login_count", @complex_context) 
      end,
      "string_concatenation" => fn -> 
        ExJexl.eval(~s(user.profile.name + " <" + user.profile.email + ">"), @complex_context) 
      end,
      "nested_transforms" => fn -> 
        ExJexl.eval("data.users|length > 2 && metrics.response_times|sort|first < 10.0", @complex_context) 
      end,
      "business_rule" => fn ->
        ExJexl.eval(
          "metrics.success_rate >= 0.9 && metrics.error_count < 5 && data.items|length > 0", 
          @complex_context
        )
      end
    }, time: 3, memory_time: 1)
  end
  
  defp benchmark_parsing_vs_evaluation do
    IO.puts("\n⚡ Benchmarking Parsing vs Evaluation")
    
    expression = "user.profile.name != null && data.users|length > 0"
    
    Benchee.run(%{
      "parse_only" => fn -> ExJexl.Parser.parse(expression) end,
      "full_eval" => fn -> ExJexl.eval(expression, @complex_context) end,
      "eval_with_cached_ast" => fn -> 
        {:ok, ast} = ExJexl.Parser.parse(expression)
        ExJexl.Evaluator.eval(ast, @complex_context)
      end
    }, time: 3, memory_time: 1)
  end
  
  defp benchmark_context_types do
    IO.puts("\n📋 Benchmarking Different Context Types")
    
    string_context = %{"name" => "Alice", "age" => 30}
    atom_context = %{name: "Alice", age: 30}
    mixed_context = %{"name" => "Alice", :age => 30}
    
    Benchee.run(%{
      "string_keys" => fn -> ExJexl.eval("name", string_context) end,
      "atom_keys" => fn -> ExJexl.eval("name", atom_context) end,
      "mixed_keys" => fn -> ExJexl.eval("name", mixed_context) end,
      "large_context_string" => fn -> ExJexl.eval("data.items[0]", @complex_context) end,
      "large_context_access" => fn -> ExJexl.eval("user.profile.settings.theme", @complex_context) end
    }, time: 2, memory_time: 1)
  end
end

# Run the benchmarks when this script is executed
ExJexlBenchmark.run_benchmarks()