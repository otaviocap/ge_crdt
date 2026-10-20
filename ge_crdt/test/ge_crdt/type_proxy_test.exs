defmodule GeCrdt.TypeProxyTest do
  use ExUnit.Case, async: true

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
        flunk("replicas did not converge in time")

      true ->
        Process.sleep(10)
        poll(fun, deadline)
    end
  end

  defp proxy_group(name) do
    {:type_proxy_test, name, System.unique_integer([:positive, :monotonic])}
  end

  test "type modules start replicas and mutate them with no explicit neighbours" do
    group = proxy_group(:counter)

    {:ok, a} =
      Causal.start_link(GCounter, "a", sync_interval: :manual, discovery: [group: group])

    {:ok, b} =
      Causal.start_link(GCounter, "b", sync_interval: :manual, discovery: [group: group])

    assert Causal.mutate(a, :increment, [2]) == :ok
    assert Causal.mutate(b, :increment, [3]) == :ok
    Causal.sync(a)
    Causal.sync(b)

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Causal.read(b) == 5 end)
  end

  test "set replicas: add/remove/read against live peers" do
    group = proxy_group(:set)

    {:ok, a} =
      Causal.start_link(AWORSet, "a", sync_interval: :manual, discovery: [group: group])

    {:ok, b} =
      Causal.start_link(AWORSet, "b", sync_interval: :manual, discovery: [group: group])

    assert Causal.mutate(a, :add, ["apple"]) == :ok
    Causal.sync(a)
    await(fn -> Causal.read(b) == MapSet.new(["apple"]) end)

    assert Causal.mutate(a, :remove, ["apple"]) == :ok
    Causal.sync(a)
    await(fn -> Causal.read(b) == MapSet.new() end)
  end

  test "named replicas are addressed through atoms" do
    {:ok, _} = Causal.start_link(GCounter, "a", sync_interval: :manual, name: :proxy_counter)

    assert Causal.mutate(:proxy_counter, :increment, [4]) == :ok
    assert Causal.read(:proxy_counter) == 4
  end

  test "struct calls keep the pure {state, delta} API" do
    assert {%GCounter{counts: %{"x" => 1}}, %GCounter{counts: %{"x" => 1}}} =
             GCounter.increment(GCounter.new("x"), 1)
  end
end
