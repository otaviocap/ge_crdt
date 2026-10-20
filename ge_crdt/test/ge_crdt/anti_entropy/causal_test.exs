defmodule GeCrdt.AntiEntropy.CausalTest do
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Types.{AWORSet, GCounter, GSet}

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

  defp start_replica(mod, id) do
    {:ok, pid} = Causal.start_link(mod, id, sync_interval: :manual)
    pid
  end

  # Unique `:pg` group per test so async tests never gossip across cases.
  defp test_group(name) do
    {:anti_entropy_test, name, System.unique_integer([:positive, :monotonic])}
  end

  defp start_discovered(mod, id, group, opts \\ []) do
    {:ok, pid} =
      Causal.start_link(
        mod,
        id,
        Keyword.merge([sync_interval: :manual, discovery: [group: group]], opts)
      )

    pid
  end

  test "mutate auto-syncs the new delta with no explicit sync call" do
    a = start_replica(GCounter, "a")
    b = start_replica(GCounter, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    # sync_interval: :manual on both, and sync/1 is never called —
    # convergence can only come from the mutate-triggered round
    Causal.mutate(a, :increment, [2])
    Causal.mutate(b, :increment, [3])

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Causal.read(b) == 5 end)
  end

  test "sync_on_mutate: false holds deltas back until the next round" do
    {:ok, a} =
      Causal.start_link(GCounter, "a", sync_interval: :manual, sync_on_mutate: false)

    {:ok, b} =
      Causal.start_link(GCounter, "b", sync_interval: :manual, sync_on_mutate: false)

    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Process.sleep(100)
    assert Causal.read(b) == 0

    Causal.sync(a)
    await(fn -> Causal.read(b) == 2 end)
  end

  test "two counters converge by gossiping delta-intervals" do
    a = start_replica(GCounter, "a")
    b = start_replica(GCounter, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Causal.mutate(b, :increment, [3])
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(a) == 5 and Causal.read(b) == 5 end)
  end

  test "mutations between rounds are batched into one interval" do
    a = start_replica(GCounter, "a")
    b = start_replica(GCounter, "b")
    Causal.set_neighbours(a, [b])

    Causal.mutate(a, :increment, [1])
    Causal.mutate(a, :increment, [1])
    Causal.mutate(a, :increment, [1])
    Causal.sync(a)

    await(fn -> Causal.read(b) == 3 end)
    assert Causal.state(b).counts == Causal.state(a).counts
  end

  test "id-less types work: GSet replicas converge" do
    a = start_replica(GSet, "a")
    b = start_replica(GSet, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :add, [1])
    Causal.mutate(b, :add, [2])
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(a) == MapSet.new([1, 2]) end)
    await(fn -> Causal.read(b) == MapSet.new([1, 2]) end)
  end

  test "add-wins set: adds and observed removes propagate" do
    a = start_replica(AWORSet, "a")
    b = start_replica(AWORSet, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :add, ["apple"])
    Causal.sync(a)
    Causal.sync(b)
    await(fn -> Causal.read(b) == MapSet.new(["apple"]) end)

    Causal.mutate(a, :remove, ["apple"])
    Causal.sync(a)
    Causal.sync(b)
    await(fn -> Causal.read(a) == MapSet.new() end)
    await(fn -> Causal.read(b) == MapSet.new() end)
  end

  test "transitive propagation along a chain a -> b -> c" do
    a = start_replica(AWORSet, "a")
    b = start_replica(AWORSet, "b")
    c = start_replica(AWORSet, "c")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [c])
    Causal.set_neighbours(c, [])

    Causal.mutate(a, :add, ["x"])
    Causal.sync(a)
    await(fn -> Causal.read(b) == MapSet.new(["x"]) end)

    # c never talks to a; b forwards the buffered delta-interval
    Causal.sync(b)
    await(fn -> Causal.read(c) == MapSet.new(["x"]) end)
  end

  test "duplicate deliveries are idempotent" do
    a = start_replica(GCounter, "a")
    b = start_replica(GCounter, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [5])
    Causal.sync(a)
    await(fn -> Causal.read(b) == 5 end)

    before = Causal.state(a)
    # replay b's whole state at a with bogus metadata; a must ignore it
    send(a, {:ge_crdt_delta, self(), Causal.state(b), 999, 0})
    Process.sleep(50)
    assert Causal.state(a) == before

    # a settled round-trip changes nothing either
    Causal.sync(a)
    Causal.sync(b)
    Process.sleep(50)
    assert Causal.state(a) == before
    assert Causal.read(b) == 5
  end

  test "new member receives the full state after history was collected" do
    a = start_replica(AWORSet, "a")
    b = start_replica(AWORSet, "b")
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :add, ["x"])
    Causal.mutate(a, :add, ["y"])
    Causal.sync(a)
    await(fn -> Causal.read(b) == MapSet.new(["x", "y"]) end)

    # second round: b's ack lets a garbage-collect its whole buffer
    Causal.sync(a)
    assert :sys.get_state(a).buffer == %{}

    c = start_replica(AWORSet, "c")
    Causal.set_neighbours(a, [b, c])
    Causal.sync(a)

    # c never acknowledged anything and the interval history is gone,
    # so only the full-state fallback can converge it
    await(fn -> Causal.read(c) == MapSet.new(["x", "y"]) end)
  end

  test "periodic timer gossips without manual sync" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: 10)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: 10)

    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [7])

    await(fn -> Causal.read(b) == 7 end)
    await(fn -> Causal.read(a) == 7 end)
  end

  test "replicas sharing a discovery group gossip with no manual neighbours" do
    group = test_group(:auto_join)
    a = start_discovered(GCounter, "a", group)
    b = start_discovered(GCounter, "b", group)

    Causal.mutate(a, :increment, [2])
    Causal.mutate(b, :increment, [3])
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Causal.read(b) == 5 end)
  end

  test "late joiner is discovered and converged automatically" do
    group = test_group(:late_joiner)
    a = start_discovered(GCounter, "a", group)
    b = start_discovered(GCounter, "b", group)

    Causal.mutate(a, :increment, [4])
    Causal.sync(a)
    Causal.sync(b)
    await(fn -> Causal.read(b) == 4 end)

    c = start_discovered(GCounter, "c", group)
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(c) == 4 end)
  end

  test "manual neighbours compose with discovered ones" do
    group = test_group(:union)
    a = start_discovered(GCounter, "a", group)
    b = start_discovered(GCounter, "b", group)
    d = start_replica(GCounter, "d")
    Causal.set_neighbours(a, [d])

    Causal.mutate(a, :increment, [6])
    Causal.sync(a)

    await(fn -> Causal.read(b) == 6 end)
    await(fn -> Causal.read(d) == 6 end)
  end

  test "custom scopes work and default groups are separated per type" do
    a = start_discovered(GCounter, "a", :iso_group, scope: :iso_scope)
    b = start_discovered(GCounter, "b", :iso_group, scope: :iso_scope)

    Causal.mutate(a, :increment, [1])
    Causal.sync(a)

    await(fn -> Causal.read(b) == 1 end)

    # `discovery: true` puts each CRDT module in its own group, so
    # different types never become neighbours of each other
    {:ok, gc} = Causal.start_link(GCounter, "gc", sync_interval: :manual, discovery: true)

    {:ok, aw} =
      Causal.start_link(AWORSet, "aw", sync_interval: :manual, discovery: true)

    assert :pg.get_members(:pg, GCounter) == [gc]
    assert :pg.get_members(:pg, AWORSet) == [aw]
  end

  test "fully automatic end-to-end over the timer with discovery only" do
    group = test_group(:auto_timer)
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: 10, discovery: [group: group])
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: 10, discovery: [group: group])

    Causal.mutate(a, :increment, [9])

    await(fn -> Causal.read(a) == 9 end)
    await(fn -> Causal.read(b) == 9 end)
  end
end
