defmodule GeCrdt.Utils.DotKernelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GeCrdt.Utils.{DotContext, DotKernel}

  defp replica_gen, do: StreamData.member_of([:a, :b, :c])

  defp value_gen, do: StreamData.integer(0..50)

  defp dot_gen do
    gen all(
          id <- replica_gen(),
          n <- StreamData.integer(1..10)
        ) do
      {id, n}
    end
  end

  defp kernel_gen(max_ops \\ 12) do
    gen all(
          ops <-
            StreamData.list_of(
              gen all(
                    id <- replica_gen(),
                    v <- value_gen()
                  ) do
                {id, v}
              end,
              max_length: max_ops
            )
        ) do
      Enum.reduce(ops, DotKernel.new(), fn {id, v}, acc ->
        {next, _delta} = DotKernel.add(acc, id, v)
        next
      end)
    end
  end

  describe "new/0" do
    test "is empty" do
      assert DotKernel.new() == %DotKernel{dot_store: %{}, context: DotContext.new()}
      assert DotKernel.values(DotKernel.new()) == []
      assert DotKernel.dots(DotKernel.new()) == []
    end
  end

  describe "add/3" do
    test "stores the value under a fresh dot" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, :x)
      assert DotKernel.values(k1) == [:x]
      assert DotKernel.dots(k1) == [{:a, 1}]
      assert DotContext.dot_in?(k1.context, {:a, 1})
    end

    test "sequential adds for the same replica bump the counter" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :a, 2)
      assert Enum.sort(DotKernel.dots(k2)) == [{:a, 1}, {:a, 2}]
      assert Enum.sort(DotKernel.values(k2)) == [1, 2]
      assert DotContext.max_for(k2.context, :a) == 2
    end

    test "adds for different replicas are independent" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :b, 2)
      assert Enum.sort(DotKernel.dots(k2)) == [{:a, 1}, {:b, 1}]
    end

    test "delta holds exactly the new dot and joins back to the new state" do
      k0 = DotKernel.new()
      {k1, delta} = DotKernel.add(k0, :a, 10)

      assert delta.dot_store == %{{:a, 1} => 10}
      assert DotContext.dot_in?(delta.context, {:a, 1})

      assert DotKernel.join(k0, delta) == k1
      assert DotKernel.join(k1, delta) == k1
    end

    test "delta context is minimal (only the new dot)" do
      {_k1, delta} = DotKernel.add(DotKernel.new(), :a, 1)
      assert delta.context == DotContext.insert_dot(DotContext.new(), {:a, 1})
    end
  end

  describe "remove_dot/2" do
    test "removes the dot and returns a causal delta" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :a, 2)
      {k3, delta} = DotKernel.remove_dot(k2, {:a, 1})

      assert Enum.sort(DotKernel.dots(k3)) == [{:a, 2}]
      assert delta.dot_store == %{}
      assert DotContext.dot_in?(delta.context, {:a, 1})
    end

    test "missing dot is a no-op returning an empty delta" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      assert DotKernel.remove_dot(k1, {:a, 99}) == {k1, DotKernel.new()}
    end

    test "remove wins over a concurrent join" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :a, 2)
      {k3, _delta} = DotKernel.remove_dot(k2, {:a, 1})

      assert Enum.sort(DotKernel.dots(DotKernel.join(k3, k2))) == [{:a, 2}]
    end
  end

  describe "remove_value/2" do
    test "removes every dot carrying the value" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, :dup)
      {k2, _} = DotKernel.add(k1, :b, :dup)
      {k3, _} = DotKernel.add(k2, :c, :keep)
      {k4, delta} = DotKernel.remove_value(k3, :dup)

      assert DotKernel.values(k4) == [:keep]
      assert delta.dot_store == %{}
      assert DotContext.dot_in?(delta.context, {:a, 1})
      assert DotContext.dot_in?(delta.context, {:b, 1})
      refute DotContext.dot_in?(delta.context, {:c, 1})
    end

    test "missing value keeps the state and returns an empty delta" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      assert DotKernel.remove_value(k1, :nope) == {k1, DotKernel.new()}
    end

    test "removed values stay removed after joining with the pre-remove state" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :b, 2)
      {k3, _} = DotKernel.remove_value(k2, 1)
      assert DotKernel.values(DotKernel.join(k3, k2)) == [2]
    end
  end

  describe "remove_all/1" do
    test "clears the store and returns full causal delta" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :b, 2)
      {k3, delta} = DotKernel.remove_all(k2)

      assert DotKernel.values(k3) == []
      assert DotKernel.dots(k3) == []
      assert delta.dot_store == %{}
      assert DotContext.dot_in?(delta.context, {:a, 1})
      assert DotContext.dot_in?(delta.context, {:b, 1})

      assert k3.context == k2.context
    end

    test "remove_all on empty is a no-op" do
      assert DotKernel.remove_all(DotKernel.new()) == {DotKernel.new(), DotKernel.new()}
    end

    test "cleared dots stay cleared after joining with the pre-clear state" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :b, 2)
      {k3, _} = DotKernel.remove_all(k2)
      assert DotKernel.join(k3, k2) == k3
    end
  end

  describe "join/2" do
    test "join with empty is identity" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      assert DotKernel.join(k1, DotKernel.new()) == k1
      assert DotKernel.join(DotKernel.new(), k1) == k1
    end

    test "join is idempotent" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      assert DotKernel.join(k1, k1) == k1
    end

    test "join keeps disjoint dots from both sides" do
      {ka, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {kb, _} = DotKernel.add(DotKernel.new(), :b, 2)
      joined = DotKernel.join(ka, kb)
      assert Enum.sort(DotKernel.values(joined)) == [1, 2]
    end

    test "shallow join on same dot with conflicting values keeps the left value" do
      mk = fn v ->
        %DotKernel{
          dot_store: %{{:a, 1} => v},
          context: DotContext.insert_dot(DotContext.new(), {:a, 1})
        }
      end

      assert DotKernel.join(mk.(1), mk.(2)).dot_store == %{{:a, 1} => 1}
    end

    test "join merges contexts" do
      {ka, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {kb, _} = DotKernel.add(DotKernel.new(), :b, 1)
      joined = DotKernel.join(ka, kb)
      assert joined.context == DotContext.join(ka.context, kb.context)
    end
  end

  describe "deep_join/2" do
    test "merges concurrent payloads under the same dot with Join.join/2" do
      mk = fn v ->
        %DotKernel{
          dot_store: %{{:a, 1} => v},
          context: DotContext.insert_dot(DotContext.new(), {:a, 1})
        }
      end

      assert DotKernel.deep_join(mk.(1), mk.(2)).dot_store == %{{:a, 1} => 2}

      assert DotKernel.deep_join(mk.(MapSet.new([1])), mk.(MapSet.new([2]))).dot_store == %{
               {:a, 1} => MapSet.new([1, 2])
             }
    end

    test "deep_join with disjoint dots behaves like join" do
      {ka, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {kb, _} = DotKernel.add(DotKernel.new(), :b, 2)
      assert DotKernel.deep_join(ka, kb) == DotKernel.join(ka, kb)
    end

    test "deep_join with empty is identity" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 5)
      assert DotKernel.deep_join(k1, DotKernel.new()) == k1
    end
  end

  describe "values/1 and dots/1" do
    test "mirror the underlying store" do
      {k1, _} = DotKernel.add(DotKernel.new(), :a, 1)
      {k2, _} = DotKernel.add(k1, :b, 2)
      assert Enum.sort(DotKernel.dots(k2)) == Enum.sort(Map.keys(k2.dot_store))
      assert Enum.sort(DotKernel.values(k2)) == Enum.sort(Map.values(k2.dot_store))
    end
  end

  property "add grows the store by one and the delta rejoins to the new state" do
    check all(
            k <- kernel_gen(),
            id <- replica_gen(),
            v <- value_gen()
          ) do
      size_before = map_size(k.dot_store)
      {k2, delta} = DotKernel.add(k, id, v)

      assert map_size(k2.dot_store) == size_before + 1
      assert DotKernel.join(k, delta) == k2
      assert DotKernel.join(k2, delta) == k2
      assert delta.dot_store |> Map.values() == [v]
    end
  end

  property "fresh dots are unique and covered by the new context" do
    check all(
            k <- kernel_gen(),
            id <- replica_gen(),
            v <- value_gen()
          ) do
      {k2, delta} = DotKernel.add(k, id, v)
      [fresh] = Map.keys(delta.dot_store) -- Map.keys(k.dot_store)

      refute fresh in DotKernel.dots(k)
      assert fresh in DotKernel.dots(k2)
      assert DotContext.dot_in?(k2.context, fresh)
      assert DotContext.dot_in?(delta.context, fresh)
    end
  end

  property "remove_dot drops the dot and the delta context covers it" do
    check all(
            k <- kernel_gen(),
            dot <- dot_gen()
          ) do
      {k2, delta} = DotKernel.remove_dot(k, dot)

      if Map.has_key?(k.dot_store, dot) do
        refute Map.has_key?(k2.dot_store, dot)
        assert DotContext.dot_in?(delta.context, dot)

        refute Map.has_key?(DotKernel.join(k2, k).dot_store, dot)
      else
        assert k2 == k
        assert delta == DotKernel.new()
      end
    end
  end

  property "remove_value drops exactly the matching entries" do
    check all(
            k <- kernel_gen(),
            v <- value_gen()
          ) do
      {k2, _delta} = DotKernel.remove_value(k, v)
      assert Enum.all?(DotKernel.values(k2), &(&1 != v))

      expected_kept =
        Enum.reject(k.dot_store, fn {_d, val} -> val == v end) |> Map.new()

      assert k2.dot_store == expected_kept
    end
  end

  property "remove_all empties the store but keeps causal history" do
    check all(k <- kernel_gen()) do
      {k2, delta} = DotKernel.remove_all(k)
      assert k2.dot_store == %{}
      assert k2.context == k.context
      assert delta.dot_store == %{}

      for d <- Map.keys(k.dot_store) do
        assert DotContext.dot_in?(delta.context, d)
      end

      assert DotKernel.join(k2, k) == k2
    end
  end

  property "join with empty is identity and join is idempotent" do
    check all(k <- kernel_gen()) do
      assert DotKernel.join(k, DotKernel.new()) == k
      assert DotKernel.join(DotKernel.new(), k) == k
      assert DotKernel.join(k, k) == k
      assert DotKernel.deep_join(k, k) == k
    end
  end

  property "join is associative; disjoint joins commute" do
    check all(
            a <- kernel_gen(),
            b <- kernel_gen(),
            c <- kernel_gen()
          ) do
      assert DotKernel.join(DotKernel.join(a, b), c) == DotKernel.join(a, DotKernel.join(b, c))

      assert DotKernel.deep_join(a, b) == DotKernel.deep_join(b, a)
    end
  end

  property "join keeps every dot unseen by the other side" do
    check all(
            a <- kernel_gen(),
            b <- kernel_gen()
          ) do
      joined = DotKernel.join(a, b)

      for {dot, val} <- a.dot_store, not DotContext.dot_in?(b.context, dot) do
        assert Map.get(joined.dot_store, dot) == val
      end

      for {dot, val} <- b.dot_store, not DotContext.dot_in?(a.context, dot) do
        assert Map.get(joined.dot_store, dot) == val
      end
    end
  end

  property "dots/values mirror the store" do
    check all(k <- kernel_gen()) do
      assert Enum.sort(DotKernel.dots(k)) == Enum.sort(Map.keys(k.dot_store))
      assert Enum.sort(DotKernel.values(k)) == Enum.sort(Map.values(k.dot_store))
    end
  end

  property "concurrent adds from disjoint replica sets converge under join" do
    check all(
            ops_a <- StreamData.list_of(value_gen(), max_length: 5),
            ops_b <- StreamData.list_of(value_gen(), max_length: 5)
          ) do
      ka =
        Enum.reduce(ops_a, DotKernel.new(), fn v, acc -> elem(DotKernel.add(acc, :a, v), 0) end)

      kb =
        Enum.reduce(ops_b, DotKernel.new(), fn v, acc -> elem(DotKernel.add(acc, :b, v), 0) end)

      assert DotKernel.join(ka, kb) == DotKernel.join(kb, ka)

      converged = DotKernel.join(ka, kb)
      assert Enum.sort(DotKernel.values(converged)) == Enum.sort(ops_a ++ ops_b)
    end
  end
end
