defmodule GeCrdt.Types.GCounterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.GCounter

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      map(member_of(1..3), fn n -> {:mutate, id, :increment, [n]} end)
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for every increment" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            amount <- member_of(1..3),
            max_runs: 40
          ) do
      state = GCounter |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      {new_state, delta} = GCounter.increment(state, amount)
      assert GCounter.join(state, delta) == new_state
    end
  end

  property "same operations in any order converge after merge" do
    check all(
            ops0 <- list_of(mutate_gen(), max_length: 8),
            perm_a <- H.permutation(H.strip_ids(ops0)),
            perm_b <- H.permutation(H.strip_ids(ops0)),
            max_runs: 40
          ) do
      ops = H.strip_ids(ops0)
      states = H.build_all(GCounter, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(GCounter, states)
      assert H.queries_of(GCounter, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: 40) do
      final = GCounter |> H.run(@ids, script) |> then(&H.mesh(GCounter, &1, @ids))
      assert H.converged_queries(GCounter, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "value equals the total incremented (no loss)" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: 40) do
      total = Enum.reduce(ops, 0, fn {:mutate, _id, :increment, [n]}, acc -> acc + n end)
      final = ops |> then(&H.run(GCounter, @ids, &1)) |> then(&H.mesh(GCounter, &1, @ids))

      assert Enum.all?(H.converged_queries(GCounter, final), &(&1 == total))
    end
  end
end
