defmodule GeCrdt.Types.TwoPSetPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.TwoPSet

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      bind(member_of([:add, :remove]), fn op ->
        map(member_of(0..4), fn v -> {:mutate, id, op, [v]} end)
      end)
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for add and remove" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:add, :remove]),
            v <- member_of(0..4),
            max_runs: 40
          ) do
      state = TwoPSet |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      {new_state, delta} = apply(TwoPSet, op, [state, v])
      assert TwoPSet.join(state, delta) == new_state
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
      states = H.build_all(TwoPSet, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(TwoPSet, states)
      assert H.queries_of(TwoPSet, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: 40) do
      final = TwoPSet |> H.run(@ids, script) |> then(&H.mesh(TwoPSet, &1, @ids))
      assert H.converged_queries(TwoPSet, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "removed elements never reappear" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: 40) do
      {added, removed} =
        Enum.reduce(ops, {MapSet.new(), MapSet.new()}, fn
          {:mutate, _id, :add, [v]}, {a, r} -> {MapSet.put(a, v), r}
          {:mutate, _id, :remove, [v]}, {a, r} -> {a, MapSet.put(r, v)}
        end)

      final = ops |> then(&H.run(TwoPSet, @ids, &1)) |> then(&H.mesh(TwoPSet, &1, @ids))

      assert Enum.all?(H.converged_queries(TwoPSet, final), fn read ->
               MapSet.disjoint?(read, removed) and MapSet.subset?(read, added)
             end)
    end
  end
end
