defmodule GeCrdt.AntiEntropy.FacadeTest do
  use ExUnit.Case, async: true

  alias GeCrdt.AntiEntropy
  alias GeCrdt.AntiEntropy.Basic
  alias GeCrdt.AntiEntropy.Causal
  alias GeCrdt.Types.GCounter

  defmodule TinyCounter do
    @moduledoc false
    @behaviour GeCrdt.Type

    defstruct id: nil, counts: %{}

    def new(id \\ nil), do: %__MODULE__{id: id}

    def join(a, b) do
      %__MODULE__{
        id: a.id || b.id,
        counts: Map.merge(a.counts, b.counts, fn _, x, y -> max(x, y) end)
      }
    end

    def bump(%__MODULE__{id: id, counts: m} = st, n \\ 1) do
      v = Map.get(m, id, 0) + n
      {%{st | counts: Map.put(m, id, v)}, %__MODULE__{counts: %{id => v}}}
    end

    def value(%__MODULE__{counts: m}), do: Enum.sum(Map.values(m))
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

  test "facade defaults to the Causal implementation" do
    {:ok, a} = AntiEntropy.start_link(GCounter, "a", sync_interval: :manual)

    assert %Causal{} = :sys.get_state(a)
  end

  test "implementation swaps via application env" do
    previous = Application.get_env(:ge_crdt, :anti_entropy)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:ge_crdt, :anti_entropy)
      else
        Application.put_env(:ge_crdt, :anti_entropy, previous)
      end
    end)

    Application.put_env(:ge_crdt, :anti_entropy, Basic)

    {:ok, a} = AntiEntropy.start_link(GCounter, "a", sync_interval: :manual)
    {:ok, b} = AntiEntropy.start_link(GCounter, "b", sync_interval: :manual)

    assert %Basic{} = :sys.get_state(a)

    AntiEntropy.set_neighbours(a, [b])
    AntiEntropy.set_neighbours(b, [a])
    AntiEntropy.mutate(a, :increment, [2])
    AntiEntropy.mutate(b, :increment, [3])

    await(fn -> AntiEntropy.read(a) == 5 end)
    await(fn -> AntiEntropy.read(b) == 5 end)
  end

  test "custom Type plugs into replicas end to end" do
    {:ok, a} = Causal.start_link(TinyCounter, "a", sync_interval: :manual)
    {:ok, b} = Causal.start_link(TinyCounter, "b", sync_interval: :manual)
    Causal.set_neighbours(a, [b])
    Causal.set_neighbours(b, [a])

    Causal.mutate(a, :bump, [2])
    Causal.mutate(b, :bump, [3])

    await(fn -> Causal.read(a) == 5 end)
    await(fn -> Causal.read(b) == 5 end)
  end
end
