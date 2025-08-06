defmodule ScalingBench do
  @moduledoc """
  Benchmark ExJexl performance scaling with expression complexity.
  """

  def run do
    IO.puts("📈 ExJexl Scaling Performance Analysis")
    IO.puts(String.duplicate("=", 50))
    
    # Create contexts of different sizes
    small_ctx = %{"a" => 1, "b" => 2, "c" => 3}
    medium_ctx = 1..50 |> Enum.reduce(%{}, fn i, acc -> 
      Map.put(acc, "key#{i}", i) 
    end)
    large_ctx = 1..500 |> Enum.reduce(%{}, fn i, acc -> 
      Map.put(acc, "key#{i}", %{"value" => i, "data" => [i, i*2, i*3]}) 
    end)
    
    # Array size scaling
    IO.puts("\n🔢 Array Size Impact")
    Benchee.run(%{
      "array_5_items" => fn -> ExJexl.eval("[1,2,3,4,5]") end,
      "array_10_items" => fn -> ExJexl.eval("[1,2,3,4,5,6,7,8,9,10]") end,
      "array_20_items" => fn -> ExJexl.eval("[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]") end
    }, time: 1, memory_time: 0.5)
    
    # Context size scaling
    IO.puts("\n📋 Context Size Impact")
    Benchee.run(%{
      "small_context" => fn -> ExJexl.eval("a + b + c", small_ctx) end,
      "medium_context" => fn -> ExJexl.eval("key1 + key25 + key50", medium_ctx) end,
      "large_context" => fn -> ExJexl.eval("key1.value + key250.value + key500.value", large_ctx) end
    }, time: 1, memory_time: 0.5)
    
    # Expression complexity scaling
    IO.puts("\n🎯 Expression Complexity Impact")
    Benchee.run(%{
      "simple_1_op" => fn -> ExJexl.eval("2 + 3") end,
      "medium_5_ops" => fn -> ExJexl.eval("1 + 2 * 3 - 4 / 2") end,
      "complex_10_ops" => fn -> ExJexl.eval("(1 + 2) * (3 - 4) + (5 * 6) - (7 / 2) + (8 % 3)") end,
      "very_complex_20_ops" => fn -> 
        ExJexl.eval("((1 + 2) * (3 - 4) + (5 * 6) - (7 / 2)) * ((8 + 9) / (10 - 5)) + ((11 * 12) - (13 + 14)) / ((15 - 16) + (17 * 18))") 
      end
    }, time: 1, memory_time: 0.5)
    
    # Property access depth
    nested_ctx = %{
      "level1" => %{
        "level2" => %{
          "level3" => %{
            "level4" => %{
              "level5" => %{
                "value" => "deep_value"
              }
            }
          }
        }
      }
    }
    
    IO.puts("\n🔍 Property Access Depth Impact")
    Benchee.run(%{
      "depth_1" => fn -> ExJexl.eval("level1", nested_ctx) end,
      "depth_2" => fn -> ExJexl.eval("level1.level2", nested_ctx) end,
      "depth_3" => fn -> ExJexl.eval("level1.level2.level3", nested_ctx) end,
      "depth_5" => fn -> ExJexl.eval("level1.level2.level3.level4.level5.value", nested_ctx) end
    }, time: 1, memory_time: 0.5)
    
    IO.puts("\n✅ Scaling analysis completed!")
  end
end

ScalingBench.run()