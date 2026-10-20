defmodule GeCrdt.ReadmeTest do
  @moduledoc """
  One test per executable snippet in `README.md`.

  These tests are intentionally written with the same public API calls
  shown in the README, so the examples stay runnable and correct.
  """

  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.{Basic, Causal}
  alias GeCrdt.Types.{AWLWWSet, AWORSet, EWFlag, GCounter, GSet, LexCounter}
  alias GeCrdt.Types.{MVReg, ORMap, PNCounter, RWSet, TwoPSet}
  alias GeCrdt.Utils.{DotContext, DotKernel}

  defp await(fun, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("gossip did not converge in time")

      true ->
        Process.sleep(10)
        poll(fun, deadline)
    end
  end

  test "simple example: add-wins or-set" do
    sx = AWORSet.new("x")
    sy = AWORSet.new("y")

    {sx, _} = AWORSet.add(sx, "apple")
    {sx, _} = AWORSet.remove(sx, "apple")

    {sy, _} = AWORSet.add(sy, "juice")
    {sy, _} = AWORSet.add(sy, "apple")

    assert AWORSet.join(sx, sy) |> AWORSet.read() == MapSet.new(["apple", "juice"])
  end

  test "simple example: remove-wins or-set" do
    sx = RWSet.new("x")
    sy = RWSet.new("y")

    {sx, _} = RWSet.add(sx, "apple")
    {sx, _} = RWSet.remove(sx, "apple")

    {sy, _} = RWSet.add(sy, "juice")
    {sy, _} = RWSet.add(sy, "apple")

    assert RWSet.join(sx, sy) |> RWSet.read() == MapSet.new(["juice"])
  end

  test "example with delta mutations: GSet" do
    sx = GSet.new()

    {sx, _} = GSet.add(sx, 1)
    {sx, _} = GSet.add(sx, 4)

    sy = sx

    {sy, d1} = GSet.add(sy, 2)
    {sy, d2} = GSet.add(sy, 3)
    dy = GSet.join(d1, d2)

    assert GSet.read(sy) == MapSet.new([1, 2, 3, 4])
    assert GSet.read(dy) == MapSet.new([2, 3])
    assert GSet.read(sx) == MapSet.new([1, 4])

    assert GSet.join(sx, dy) |> GSet.read() == MapSet.new([1, 2, 3, 4])
  end

  test "catalog: GSet" do
    a = GSet.new()
    b = GSet.new()

    {a, _} = GSet.add(a, "red")
    {b, _} = GSet.add(b, "blue")

    assert GSet.join(a, b) |> GSet.read() == MapSet.new(["red", "blue"])
  end

  test "catalog: TwoPSet" do
    a = TwoPSet.new()
    b = TwoPSet.new()

    {a, _} = TwoPSet.add(a, 3.1415)
    {a, _} = TwoPSet.remove(a, 3.1415)
    {b, _} = TwoPSet.add(b, 42)
    {b, _} = TwoPSet.add(b, 3.1415)

    assert TwoPSet.join(a, b) |> TwoPSet.read() == MapSet.new([42])

    c = GSet.new()
    {c, _} = GSet.add(c, 42)

    assert TwoPSet.join(a, b) |> TwoPSet.read() == GSet.read(c)
  end

  test "catalog: GCounter" do
    x = GCounter.new("x")
    y = GCounter.new("y")
    z = GCounter.new("z")

    {x, _} = GCounter.increment(x)
    {x, _} = GCounter.increment(x)
    {y, _} = GCounter.increment(y, 2)
    z = z |> GCounter.join(x) |> GCounter.join(y)

    assert GCounter.value(z) == 4

    {x, _} = GCounter.increment(x, 2)
    {z, _} = GCounter.increment(z, 2)
    z = z |> GCounter.join(x) |> GCounter.join(x)

    assert GCounter.value(z) == 8
    assert z.counts == %{"x" => 4, "y" => 2, "z" => 2}
  end

  test "catalog: PNCounter" do
    x = PNCounter.new("a")
    y = PNCounter.new("b")

    {x, _} = PNCounter.increment(x, 4)
    {x, _} = PNCounter.decrement(x)
    {y, _} = PNCounter.decrement(y)

    refute PNCounter.value(x) == PNCounter.value(y)

    x = PNCounter.join(x, y)
    y = PNCounter.join(y, x)

    assert PNCounter.value(x) == 2
    assert PNCounter.value(y) == 2
  end

  test "catalog: LexCounter" do
    x = LexCounter.new("a")
    y = LexCounter.new("b")

    {x, _} = LexCounter.increment(x, 4)
    {x, _} = LexCounter.decrement(x)
    {y, _} = LexCounter.decrement(y)

    refute LexCounter.value(x) == LexCounter.value(y)

    x = LexCounter.join(x, y)
    y = LexCounter.join(y, x)

    assert LexCounter.value(x) == 2
    assert LexCounter.value(y) == 2
  end

  test "catalog: DotKernel" do
    k = DotKernel.new()
    {k, _} = DotKernel.add(k, "x", :apple)
    assert DotKernel.values(k) == [:apple]

    {k, delta} = DotKernel.remove_value(k, :apple)
    assert DotKernel.values(k) == []
    assert DotContext.dot_in?(delta.context, {"x", 1})
  end

  test "catalog: AWORSet" do
    x = AWORSet.new("a")
    y = AWORSet.new("b")

    {x, _} = AWORSet.add(x, 3.14)
    {x, _} = AWORSet.add(x, 2.718)
    {x, _} = AWORSet.remove(x, 3.14)
    {y, _} = AWORSet.add(y, 3.14)

    x = AWORSet.join(x, y)

    assert AWORSet.read(x) == MapSet.new([2.718, 3.14])

    {x, _} = AWORSet.reset(x)
    x = AWORSet.join(x, y)

    assert AWORSet.read(x) == MapSet.new()
  end

  test "catalog: RWSet" do
    x = RWSet.new("a")
    y = RWSet.new("b")

    {x, _} = RWSet.add(x, 3.14)
    {x, _} = RWSet.add(x, 2.718)
    {x, _} = RWSet.remove(x, 3.14)
    {y, _} = RWSet.add(y, 3.14)

    x = RWSet.join(x, y)

    assert RWSet.read(x) == MapSet.new([2.718])

    {x, _} = RWSet.reset(x)
    x = RWSet.join(x, y)

    assert RWSet.read(x) == MapSet.new()
  end

  test "catalog: MVReg concurrent writes" do
    x = MVReg.new("uid-x")
    y = MVReg.new("uid-y")

    {x, _} = MVReg.write(x, "hello")
    {x, _} = MVReg.write(x, "world")

    {y, _} = MVReg.write(y, "world")
    {y, _} = MVReg.write(y, "hello")

    y = MVReg.join(y, x)

    assert MVReg.read(y) == MapSet.new(["hello", "world"])

    {y, _} = MVReg.write(y, "mars")
    x = MVReg.join(x, y)

    assert MVReg.read(x) == MapSet.new(["mars"])
  end

  test "catalog: MVReg resolve" do
    a = MVReg.new("uid-a")
    b = MVReg.new("uid-b")

    {a, _} = MVReg.write(a, 0)
    {b, _} = MVReg.write(b, 3)
    a = MVReg.join(a, b)

    assert MVReg.read(a) == MapSet.new([0, 3])

    {a, _} = MVReg.resolve(a)
    assert MVReg.read(a) == MapSet.new([3])

    {a, _} = MVReg.write(a, 1)
    assert MVReg.read(a) == MapSet.new([1])
  end

  test "catalog: MVReg resolve over a partial order" do
    j = MVReg.new("uid-j")
    k = MVReg.new("uid-k")
    l = MVReg.new("uid-l")

    {j, _} = MVReg.write(j, {0, 0})
    {k, _} = MVReg.write(k, {1, 0})
    {l, _} = MVReg.write(l, {0, 1})

    j = j |> MVReg.join(k) |> MVReg.join(l)
    {j, _} = MVReg.resolve(j)

    assert MVReg.read(j) == MapSet.new([{0, 1}, {1, 0}])
  end

  test "catalog: EWFlag" do
    x = EWFlag.new("x")
    y = EWFlag.new("y")

    {x, _} = EWFlag.enable(x)
    {y, _} = EWFlag.enable(y)
    {x, _} = EWFlag.disable(x)

    assert EWFlag.join(x, y) |> EWFlag.read()

    {x, _} = EWFlag.disable(x)
    refute EWFlag.read(x)
  end

  test "catalog: ORMap" do
    mx = ORMap.new("x")
    my = ORMap.new("y")

    {mx, _} = ORMap.update(mx, "paint", RWSet.new(), &RWSet.add(&1, "blue"))
    {mx, _} = ORMap.update(mx, "sound", RWSet.new(), &RWSet.add(&1, "loud"))
    {mx, _} = ORMap.update(mx, "sound", RWSet.new(), &RWSet.add(&1, "soft"))
    {my, _} = ORMap.update(my, "paint", RWSet.new(), &RWSet.add(&1, "red"))
    {my, _} = ORMap.update(my, "number", RWSet.new(), &RWSet.add(&1, "42"))

    mx = ORMap.join(mx, my)

    assert ORMap.read(mx) == %{
             "paint" => MapSet.new(["blue", "red"]),
             "sound" => MapSet.new(["loud", "soft"]),
             "number" => MapSet.new(["42"])
           }

    {my, _} = ORMap.update(my, "number", RWSet.new(), &RWSet.remove(&1, "42"))
    mx = ORMap.join(mx, my)

    assert ORMap.read(mx)["number"] == MapSet.new()
  end

  test "catalog: ORMap erase" do
    mx = ORMap.new("x")
    my = ORMap.new("y")

    {mx, _} = ORMap.update(mx, "paint", RWSet.new(), &RWSet.add(&1, "blue"))
    {my, _} = ORMap.update(my, "paint", RWSet.new(), &RWSet.add(&1, "red"))
    mx = ORMap.join(mx, my)

    {mx, _} = ORMap.delete(mx, "paint")
    {my, _} = ORMap.update(my, "paint", RWSet.new(), &RWSet.add(&1, "green"))
    my = ORMap.join(my, mx)

    assert ORMap.read(my)["paint"] == MapSet.new(["green"])
  end

  test "catalog: nested ORMap" do
    ma = ORMap.new("alice")
    mb = ORMap.new("bob")

    {ma, _} =
      ORMap.update(ma, 23, ORMap.new(), fn inner ->
        ORMap.update(inner, "color", RWSet.new(), &RWSet.add(&1, "red at 23"))
      end)

    {ma, _} =
      ORMap.update(ma, 44, ORMap.new(), fn inner ->
        ORMap.update(inner, "color", RWSet.new(), &RWSet.add(&1, "blue at 44"))
      end)

    {mb, _} =
      ORMap.update(mb, 44, ORMap.new(), fn inner ->
        ORMap.update(inner, "sound", RWSet.new(), &RWSet.add(&1, "soft at 44"))
      end)

    ma = ORMap.join(ma, mb)

    assert ma |> ORMap.to_map() |> Map.keys() |> Enum.sort() == [23, 44]

    assert ORMap.read(ma)[44] == %{
             "color" => MapSet.new(["blue at 44"]),
             "sound" => MapSet.new(["soft at 44"])
           }
  end

  test "catalog: ORMap deltas" do
    mx = ORMap.new("x")

    {mx, _} = ORMap.update(mx, "color", RWSet.new(), &RWSet.add(&1, "red"))
    {mx, _} = ORMap.update(mx, "color", RWSet.new(), &RWSet.add(&1, "blue"))

    {mx, d1} = ORMap.delete(mx, "color")
    {_mx, d2} = ORMap.update(mx, "color", RWSet.new(), &RWSet.add(&1, "black"))

    assert ORMap.read(d1) == %{}
    assert ORMap.read(d2) == %{"color" => MapSet.new(["black"])}
    assert d2.entries["color"].kernel.dot_store == %{{"x", 3} => {"black", true}}
  end

  test "catalog: AWLWWSet" do
    s = AWLWWSet.new()

    {s, _} = AWLWWSet.add(s, "red")
    assert AWLWWSet.read(s) == MapSet.new(["red"])

    Process.sleep(1)
    {s, _} = AWLWWSet.remove(s, "red")
    assert AWLWWSet.read(s) == MapSet.new()
  end

  test "anti-entropy: Basic forwards delta-groups transitively" do
    {:ok, a} =
      Basic.start_link(AWORSet, "a",
        sync_interval: :manual,
        sync_on_mutate: false
      )

    {:ok, b} =
      Basic.start_link(AWORSet, "b",
        sync_interval: :manual,
        sync_on_mutate: false
      )

    {:ok, c} =
      Basic.start_link(AWORSet, "c",
        sync_interval: :manual,
        sync_on_mutate: false
      )

    Basic.set_neighbours(a, [b])
    Basic.set_neighbours(b, [c])
    Basic.set_neighbours(c, [])

    Basic.mutate(a, :add, ["apple"])
    Basic.sync(a)

    # Wait until b has joined the delta before asking it to forward it.
    await(fn -> Basic.read(b) == MapSet.new(["apple"]) end)

    Basic.sync(b)
    await(fn -> Basic.read(c) == MapSet.new(["apple"]) end)

    assert Basic.read(a) == MapSet.new(["apple"])
  end

  test "anti-entropy: Causal batches deltas and converges" do
    {:ok, a} =
      Causal.start_link(GCounter, "a",
        sync_interval: :manual,
        sync_on_mutate: false
      )

    {:ok, b} =
      Causal.start_link(GCounter, "b",
        sync_interval: :manual,
        sync_on_mutate: false
      )

    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Causal.mutate(a, :increment, [3])

    Causal.sync(a)
    await(fn -> Causal.read(b) == 5 end)

    # b acknowledges in the background; its next round also ships its own buffer.
    Causal.sync(b)
    await(fn -> Causal.read(a) == 5 end)

    assert {Causal.read(a), Causal.read(b)} == {5, 5}
  end
end
