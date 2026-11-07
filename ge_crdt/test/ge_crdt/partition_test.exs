defmodule GeCrdt.PartitionTest do
  @moduledoc """
  Reconciliation after partition:
  replicas diverging on opposite sides of a split converge without data
  loss once connectivity returns. Partitions are simulated by emptying
  neighbour lists (messages cannot flow); healing restores them.
  """
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Types.{AWSet, GCounter}

  defp await(fun, timeout \\ 3000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("replicas did not heal in time")

      true ->
        Process.sleep(10)
        poll(fun, deadline)
    end
  end

  test "counters on both sides of a split add up after healing" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: :manual)
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    # partition: cut every link
    Causal.set_neighbours(a, [])
    Causal.set_neighbours(b, [])

    # diverge while partitioned
    for _ <- 1..10, do: Causal.mutate(a, :increment, [1])
    for _ <- 1..7, do: Causal.mutate(b, :increment, [1])
    assert Causal.read(a) == 10
    assert Causal.read(b) == 7

    # heal: restore links, gossip explicitly, nothing lost
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(a) == 17 end)
    await(fn -> Causal.read(b) == 17 end)
  end

  test "sets keep both sides' concurrent adds after healing" do
    {:ok, a} = Causal.start_link(AWSet, "a", sync_interval: :manual)
    {:ok, b} = Causal.start_link(AWSet, "b", sync_interval: :manual)

    Causal.set_neighbours(a, [])
    Causal.set_neighbours(b, [])

    Causal.mutate(a, :add, ["apple"])
    Causal.mutate(b, :add, ["juice"])
    Causal.mutate(b, :remove, ["apple"])

    # b never saw apple: its remove is a no-op there
    assert Causal.read(a) == MapSet.new(["apple"])
    assert Causal.read(b) == MapSet.new(["juice"])

    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])
    Causal.sync(a)
    Causal.sync(b)

    # add-wins: a's apple (unobserved by b's remove) survives everywhere
    await(fn -> Causal.read(a) == MapSet.new(["apple", "juice"]) end)
    await(fn -> Causal.read(b) == MapSet.new(["apple", "juice"]) end)
  end

  test "healing is fully automatic on the gossip timer" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: 10)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: 10)
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [1])
    await(fn -> Causal.read(b) == 1 end)

    # partition mid-life
    Causal.set_neighbours(a, [])
    Causal.set_neighbours(b, [])
    Causal.mutate(a, :increment, [10])
    Causal.mutate(b, :increment, [100])
    Process.sleep(50)
    assert Causal.read(a) == 11
    assert Causal.read(b) == 101

    # heal connectivity only - no manual sync call from here on
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    await(fn -> Causal.read(a) == 111 end)
    await(fn -> Causal.read(b) == 111 end)
  end
end
