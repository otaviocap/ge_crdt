defmodule GeCrdt.AntiEntropy.BasicTest do
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.Basic
  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Types.{AWORSet, GCounter}

  defp await(fun, timeout \\ 2000) do
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

  defp start_replica(mod, id, opts \\ []) do
    {:ok, pid} = Basic.start_link(mod, id, Keyword.merge([sync_interval: :manual], opts))
    pid
  end

  test "two counters converge by broadcast" do
    a = start_replica(GCounter, "a")
    b = start_replica(GCounter, "b")
    Basic.set_neighbours(a, [b])
    Basic.set_neighbours(b, [a])

    Basic.mutate(a, :increment, [2])
    Basic.mutate(b, :increment, [3])

    await(fn -> Basic.read(a) == 5 end)
    await(fn -> Basic.read(b) == 5 end)
  end

  test "transitive mode forwards along a chain" do
    a = start_replica(AWORSet, "a")
    b = start_replica(AWORSet, "b")
    c = start_replica(AWORSet, "c")
    Basic.set_neighbours(a, [b])
    Basic.set_neighbours(b, [c])
    Basic.set_neighbours(c, [])

    Basic.mutate(a, :add, ["x"])
    await(fn -> Basic.read(b) == MapSet.new(["x"]) end)
    Basic.sync(b)
    await(fn -> Basic.read(c) == MapSet.new(["x"]) end)
  end

  test "direct mode does not forward received deltas" do
    a = start_replica(AWORSet, "a")
    b = start_replica(AWORSet, "b", transitive: false)
    c = start_replica(AWORSet, "c", transitive: false)
    Basic.set_neighbours(a, [b])
    Basic.set_neighbours(b, [c])
    Basic.set_neighbours(c, [])

    Basic.mutate(a, :add, ["x"])
    await(fn -> Basic.read(b) == MapSet.new(["x"]) end)
    Basic.sync(b)
    Basic.sync(a)
    Process.sleep(100)

    # b holds it but never forwards it
    assert Basic.read(b) == MapSet.new(["x"])
    assert Basic.read(c) == MapSet.new()
  end

  test "ship: :full converges with whole states" do
    a = start_replica(GCounter, "a", ship: :full)
    b = start_replica(GCounter, "b", ship: :full)
    Basic.set_neighbours(a, [b])
    Basic.set_neighbours(b, [a])

    Basic.mutate(a, :increment, [4])

    await(fn -> Basic.read(b) == 4 end)
  end

  test "mixed Causal/Basic deployment converges" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual)
    b = start_replica(GCounter, "b")
    Causal.set_neighbours(a, [b])
    Basic.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Basic.mutate(b, :increment, [3])

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Basic.read(b) == 5 end)
  end
end
