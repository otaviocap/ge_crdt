defmodule GeCrdt.AvailabilityTest do
  @moduledoc """
  Local availability: reads and writes on a replica complete
  without contacting other node.
  """
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Types.{AWORSet, GCounter}

  test "mutate/read/state/sync succeed with no neighbours at all" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual)

    assert Causal.mutate(a, :increment, [2]) == :ok
    assert Causal.read(a) == 2
    assert %GCounter{} = Causal.state(a)
    assert Causal.sync(a) == :ok
    assert Causal.read(a) == 2
  end

  test "queries on a fresh replica return bottom values" do
    {:ok, a} = Causal.start_link(AWORSet, "a", sync_interval: :manual)
    assert Causal.read(a) == MapSet.new()

    {:ok, c} = Causal.start_link(GCounter, "c", sync_interval: :manual)
    assert Causal.read(c) == 0
  end

  test "syncing with dead or unregistered neighbours is a harmless no-op" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual)

    dead =
      spawn(fn -> :ok end)

    Process.sleep(20)
    refute Process.alive?(dead)

    Causal.set_neighbours(a, [dead, :no_such_registered_name])
    assert Causal.sync(a) == :ok

    # the replica is still alive and responsive afterwards
    assert Causal.mutate(a, :increment, [1]) == :ok
    assert Causal.read(a) == 1
    assert Process.alive?(a)
  end

  test "replicas stay responsive while partitioned" do
    {:ok, a} = Causal.start_link(AWORSet, "a", sync_interval: :manual)

    assert Causal.mutate(a, :add, ["x"]) == :ok
    assert Causal.read(a) == MapSet.new(["x"])
  end
end
