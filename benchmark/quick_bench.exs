defmodule QuickBench do
  @moduledoc """
  Quick performance benchmark for ExJexl core operations.
  """
  
  @simple_context %{"name" => "Alice", "age" => 30, "items" => [1, 2, 3, 4, 5]}
  @complex_context %{
    "user" => %{"name" => "John", "profile" => %{"email" => "john@test.com"}},
    "data" => %{"items" => [10, 20, 30], "users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]}
  }
  
  def run do
    IO.puts("🚀 ExJexl Quick Performance Benchmark")
    IO.puts(String.duplicate("=", 50))
    
    # Core operations benchmark
    Benchee.run(%{
      "literal_integer" => fn -> ExJexl.eval("42") end,
      "literal_string" => fn -> ExJexl.eval(~s("hello")) end,
      "simple_arithmetic" => fn -> ExJexl.eval("2 + 3 * 4") end,
      "comparison" => fn -> ExJexl.eval("age > 18", @simple_context) end,
      "property_access" => fn -> ExJexl.eval("user.name", @complex_context) end,
      "nested_access" => fn -> ExJexl.eval("data.users[0].name", @complex_context) end,
      "transform_single" => fn -> ExJexl.eval("items|length", @simple_context) end,
      "transform_chained" => fn -> ExJexl.eval("items|reverse|first", @simple_context) end,
      "complex_expression" => fn -> 
        ExJexl.eval("age >= 18 && name != null", @simple_context) 
      end,
      "business_logic" => fn -> 
        ExJexl.eval("user.name != null && data.items|length > 0", @complex_context) 
      end
    }, 
    time: 1, 
    memory_time: 0.5,
    formatters: [
      Benchee.Formatters.Console,
      {Benchee.Formatters.Console, extended_statistics: true}
    ])
    
    # Parser vs Evaluator breakdown
    IO.puts("\n⚡ Parser vs Evaluator Performance")
    expression = "user.name != null && data.items|length > 0"
    
    Benchee.run(%{
      "parse_only" => fn -> ExJexl.Parser.parse(expression) end,
      "eval_only" => fn ->
        {:ok, ast} = ExJexl.Parser.parse(expression)
        ExJexl.Evaluator.eval(ast, @complex_context)
      end,
      "full_eval" => fn -> ExJexl.eval(expression, @complex_context) end
    },
    time: 1,
    memory_time: 0.5)
    
    IO.puts("\n✅ Benchmark completed!")
  end
end

QuickBench.run()