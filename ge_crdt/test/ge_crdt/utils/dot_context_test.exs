defmodule GeCrdt.Utils.DotContextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GeCrdt.Utils.DotContext

  defp replica_gen, do: StreamData.member_of([:a, :b, :c])

  defp dot_gen do
    StreamData.bind(StreamData.integer(1..10), fn _ ->
      gen all(
            id <- replica_gen(),
            n <- StreamData.integer(1..10)
          ) do
        {id, n}
      end
    end)
  end

  defp context_gen do
    gen all(dots <- StreamData.list_of(dot_gen(), max_length: 12)) do
      Enum.reduce(dots, DotContext.new(), &DotContext.insert_dot(&2, &1))
    end
  end

  describe "new/0" do
    test "is empty" do
      assert DotContext.new() == %DotContext{replica_counter: %{}, dot_cloud: MapSet.new()}
    end

    test "no dot is covered" do
      refute DotContext.dot_in?(DotContext.new(), {:a, 1})
    end

    test "max_for/2 defaults to 0" do
      assert DotContext.max_for(DotContext.new(), :missing) == 0
    end
  end

  describe "make_dot/2" do
    test "first dot for a replica is counter 1" do
      {dot, ctx} = DotContext.make_dot(DotContext.new(), :a)
      assert dot == {:a, 1}
      assert DotContext.max_for(ctx, :a) == 1
      assert DotContext.dot_in?(ctx, {:a, 1})
    end

    test "sequential dots increment" do
      {d1, c1} = DotContext.make_dot(DotContext.new(), :a)
      {d2, c2} = DotContext.make_dot(c1, :a)
      {d3, c3} = DotContext.make_dot(c2, :a)
      assert [d1, d2, d3] == [a: 1, a: 2, a: 3] |> Enum.map(fn {id, n} -> {id, n} end)
      assert DotContext.max_for(c3, :a) == 3
    end

    test "replicas are independent" do
      {_dot, ctx} =
        DotContext.new()
        |> then(fn c -> elem(DotContext.make_dot(c, :a), 1) end)
        |> then(fn c -> {nil, elem(DotContext.make_dot(c, :b), 1)} end)

      assert DotContext.max_for(ctx, :a) == 1
      assert DotContext.max_for(ctx, :b) == 1
    end

    test "fresh dot is not yet covered before creation" do
      ctx = DotContext.new()
      {dot, _} = DotContext.make_dot(ctx, :a)
      # counter is 0, so dot {a,1} must not be covered beforehand
      refute DotContext.dot_in?(ctx, dot)
    end

    test "make_dot bumps counter even over a dot cloud gap" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 5})
      assert DotContext.max_for(ctx, :a) == 0
      {{:a, n}, ctx2} = DotContext.make_dot(ctx, :a)
      assert n == 1
      assert DotContext.dot_in?(ctx2, {:a, 1})
      assert DotContext.dot_in?(ctx2, {:a, 5})
    end
  end

  describe "insert_dot/3 and compact/1" do
    test "inserted dot is covered" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 1})
      assert DotContext.dot_in?(ctx, {:a, 1})
    end

    test "insert without compact still covers the dot via the cloud" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 1}, false)
      assert DotContext.dot_in?(ctx, {:a, 1})
      assert ctx.dot_cloud |> MapSet.member?({:a, 1})
    end

    test "contiguous inserts compact into the counter" do
      ctx =
        DotContext.new()
        |> DotContext.insert_dot({:a, 3}, false)
        |> DotContext.insert_dot({:a, 2}, false)
        |> DotContext.insert_dot({:a, 1}, false)

      assert ctx.replica_counter == %{}
      compacted = DotContext.compact(ctx)
      assert compacted.replica_counter == %{a: 3}
      assert MapSet.size(compacted.dot_cloud) == 0
    end

    test "gap stays in the cloud" do
      ctx =
        DotContext.new()
        |> DotContext.insert_dot({:a, 1})
        |> DotContext.insert_dot({:a, 3})

      assert ctx.replica_counter == %{a: 1}
      assert MapSet.member?(ctx.dot_cloud, {:a, 3})
      assert DotContext.dot_in?(ctx, {:a, 1})
      assert DotContext.dot_in?(ctx, {:a, 3})
      refute DotContext.dot_in?(ctx, {:a, 2})
    end

    test "filling the gap compacts" do
      ctx =
        DotContext.new()
        |> DotContext.insert_dot({:a, 1})
        |> DotContext.insert_dot({:a, 3})
        |> DotContext.insert_dot({:a, 2})

      assert ctx.replica_counter == %{a: 3}
      assert MapSet.size(ctx.dot_cloud) == 0
    end

    test "dots at or below max are dropped as redundant" do
      ctx =
        DotContext.new()
        |> DotContext.insert_dot({:a, 1})
        |> DotContext.insert_dot({:a, 2})
        |> DotContext.insert_dot({:a, 1})

      assert ctx.replica_counter == %{a: 2}
      assert MapSet.size(ctx.dot_cloud) == 0
    end

    test "lone far dot never compacts into the counter" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 5})
      assert DotContext.max_for(ctx, :a) == 0
      assert MapSet.member?(ctx.dot_cloud, {:a, 5})
      assert DotContext.dot_in?(ctx, {:a, 5})
      refute DotContext.dot_in?(ctx, {:a, 1})
    end

    test "insert is idempotent" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 1})
      assert DotContext.insert_dot(ctx, {:a, 1}) == ctx
    end

    test "compact is idempotent" do
      ctx =
        DotContext.new()
        |> DotContext.insert_dot({:a, 1}, false)
        |> DotContext.insert_dot({:a, 3}, false)

      assert DotContext.compact(ctx) == DotContext.compact(DotContext.compact(ctx))
    end
  end

  describe "join/2 and join_all/1" do
    test "join with empty is identity" do
      ctx = DotContext.new() |> DotContext.insert_dot({:a, 1})
      assert DotContext.join(ctx, DotContext.new()) == ctx
      assert DotContext.join(DotContext.new(), ctx) == ctx
    end

    test "join takes max counters" do
      {_, a} = DotContext.make_dot(DotContext.new(), :r)
      {_, a} = DotContext.make_dot(a, :r)
      {_, b} = DotContext.make_dot(DotContext.new(), :r)
      joined = DotContext.join(a, b)
      assert DotContext.max_for(joined, :r) == 2
    end

    test "join covers dots from both sides" do
      a = DotContext.new() |> DotContext.insert_dot({:a, 1})
      b = DotContext.new() |> DotContext.insert_dot({:b, 1})
      joined = DotContext.join(a, b)
      assert DotContext.dot_in?(joined, {:a, 1})
      assert DotContext.dot_in?(joined, {:b, 1})
    end

    test "join compacts a filled gap across replicas" do
      a = DotContext.new() |> DotContext.insert_dot({:x, 1})
      b = DotContext.new() |> DotContext.insert_dot({:x, 2})
      joined = DotContext.join(a, b)
      assert joined.replica_counter == %{x: 2}
      assert MapSet.size(joined.dot_cloud) == 0
    end

    test "join_all of empty list is empty" do
      assert DotContext.join_all([]) == DotContext.new()
    end

    test "join_all equals left fold of join" do
      a = DotContext.new() |> DotContext.insert_dot({:a, 1})
      b = DotContext.new() |> DotContext.insert_dot({:b, 2})
      c = DotContext.new() |> DotContext.insert_dot({:c, 3})
      assert DotContext.join_all([a, b, c]) == DotContext.join(DotContext.join(a, b), c)
    end
  end

  property "make_dot n times yields dots 1..n, all covered" do
    check all(
            id <- replica_gen(),
            n <- StreamData.integer(1..20)
          ) do
      {_dots, ctx} =
        Enum.reduce(1..max(n, 1)//1, {[], DotContext.new()}, fn _, {dots, c} ->
          {d, c2} = DotContext.make_dot(c, id)
          {[d | dots], c2}
        end)

      assert DotContext.max_for(ctx, id) == n

      for i <- 1..n do
        assert DotContext.dot_in?(ctx, {id, i})
      end

      refute DotContext.dot_in?(ctx, {id, n + 1})
    end
  end

  property "inserted dot is always covered (compact or not)" do
    check all(
            dot <- dot_gen(),
            compact_now <- StreamData.boolean()
          ) do
      ctx = DotContext.insert_dot(DotContext.new(), dot, compact_now)
      assert DotContext.dot_in?(ctx, dot)
    end
  end

  property "compact is idempotent for arbitrary dot sets" do
    check all(dots <- StreamData.list_of(dot_gen(), max_length: 15)) do
      ctx = Enum.reduce(dots, DotContext.new(), &DotContext.insert_dot(&2, &1, false))
      once = DotContext.compact(ctx)
      assert DotContext.compact(once) == once
    end
  end

  property "every inserted dot survives compact (is still covered)" do
    check all(dots <- StreamData.list_of(dot_gen(), min_length: 1, max_length: 15)) do
      ctx = Enum.reduce(dots, DotContext.new(), &DotContext.insert_dot(&2, &1, false))
      compacted = DotContext.compact(ctx)

      for d <- Enum.uniq(dots) do
        assert DotContext.dot_in?(compacted, d),
               "expected #{inspect(d)} to be covered after compact of #{inspect(dots)}"
      end
    end
  end

  property "contiguous 1..n inserted out of order compacts fully" do
    check all(
            id <- replica_gen(),
            n <- StreamData.integer(1..15),
            order <-
              StreamData.bind(StreamData.constant(n), fn k ->
                Enum.shuffle(1..k//1) |> StreamData.constant()
              end)
          ) do
      ctx =
        Enum.reduce(order, DotContext.new(), fn i, acc ->
          DotContext.insert_dot(acc, {id, i}, false)
        end)
        |> DotContext.compact()

      assert DotContext.max_for(ctx, id) == n
      assert MapSet.size(ctx.dot_cloud) == 0
    end
  end

  property "join is commutative, idempotent and associative" do
    check all(
            a <- context_gen(),
            b <- context_gen(),
            c <- context_gen()
          ) do
      assert DotContext.join(a, b) == DotContext.join(b, a)
      assert DotContext.join(a, a) == a

      assert DotContext.join(DotContext.join(a, b), c) ==
               DotContext.join(a, DotContext.join(b, c))
    end
  end

  property "join covers the union of covered dots" do
    check all(
            a <- context_gen(),
            b <- context_gen(),
            dot <- dot_gen()
          ) do
      joined = DotContext.join(a, b)

      if DotContext.dot_in?(a, dot) or DotContext.dot_in?(b, dot) do
        assert DotContext.dot_in?(joined, dot)
      end
    end
  end

  property "join counter is at least the max of both counters" do
    check all(
            a <- context_gen(),
            b <- context_gen(),
            id <- replica_gen()
          ) do
      joined = DotContext.join(a, b)

      assert DotContext.max_for(joined, id) >=
               max(DotContext.max_for(a, id), DotContext.max_for(b, id))
    end
  end

  property "join_all folds like Enum.reduce(join)" do
    check all(ctxs <- StreamData.list_of(context_gen(), max_length: 6)) do
      assert DotContext.join_all(ctxs) ==
               Enum.reduce(ctxs, DotContext.new(), &DotContext.join(&2, &1))
    end
  end
end
