defmodule GeCrdt.SyncTest do
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Sync.FullState
  alias GeCrdt.Types.GCounter

  defmodule NullSync do
    @moduledoc false
    @behaviour GeCrdt.Sync

    @impl true
    def outgoing(_ctx, _peer), do: :skip

    @impl true
    def deliver(_peer, _message), do: :ok
  end

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

  test "FullState strategy converges like classic state-based shipping" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual, sync: FullState)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: :manual, sync: FullState)
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Causal.mutate(b, :increment, [3])

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Causal.read(b) == 5 end)
  end

  test "FullState converges a late joiner" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual, sync: FullState)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: :manual, sync: FullState)
    Causal.set_neighbours(a, [b])

    Causal.mutate(a, :increment, [4])
    Causal.sync(a)

    await(fn -> Causal.read(b) == 4 end)
  end

  test "a strategy answering :skip halts all dissemination" do
    {:ok, a} = Causal.start_link(GCounter, "a", sync_interval: :manual, sync: NullSync)
    {:ok, b} = Causal.start_link(GCounter, "b", sync_interval: :manual, sync: NullSync)
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :increment, [2])
    Causal.sync(a)
    Causal.sync(b)
    Process.sleep(100)

    # nothing is ever sent, so b stays empty while a holds its delta
    assert Causal.read(a) == 2
    assert Causal.read(b) == 0
  end
end
