defmodule GeCrdt.Types.GSetPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.GSet

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      map(member_of(0..4), fn v -> {:mutate, id, :add, [v]} end)
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for every add" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            v <- member_of(0..4),
            max_runs: H.max_runs()
          ) do
      state = GSet |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      {new_state, delta} = GSet.add(state, v)
      assert GSet.join(state, delta) == new_state
    end
  end

  property "same operations in any order converge after merge" do
    check all(
            ops0 <- list_of(mutate_gen(), max_length: 8),
            perm_a <- H.permutation(H.strip_ids(ops0)),
            perm_b <- H.permutation(H.strip_ids(ops0)),
            max_runs: H.max_runs()
          ) do
      ops = H.strip_ids(ops0)
      states = H.build_all(GSet, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(GSet, states)
      assert H.queries_of(GSet, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: H.max_runs()) do
      final = GSet |> H.run(@ids, script) |> then(&H.mesh(GSet, &1, @ids))
      assert H.converged_queries(GSet, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "read equals the union of everything added" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: H.max_runs()) do
      added =
        Enum.reduce(ops, MapSet.new(), fn {:mutate, _id, :add, [v]}, acc -> MapSet.put(acc, v) end)

      final = ops |> then(&H.run(GSet, @ids, &1)) |> then(&H.mesh(GSet, &1, @ids))

      assert Enum.all?(H.converged_queries(GSet, final), &(&1 == added))
    end
  end
end
