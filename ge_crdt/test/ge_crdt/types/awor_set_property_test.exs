defmodule GeCrdt.Types.AWORSetPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.AWORSet

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

  defp distinct_pair_gen do
    bind(member_of(0..4), fn v ->
      map(filter(member_of(0..4), &(&1 != v)), &{v, &1})
    end)
  end

  property "delta decomposition holds for add, remove and reset" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:add, :remove, :reset]),
            v <- member_of(0..4),
            max_runs: H.max_runs()
          ) do
      state = AWORSet |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      args = if op == :reset, do: [], else: [v]
      {new_state, delta} = apply(AWORSet, op, [state | args])
      assert AWORSet.join(state, delta) == new_state
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
      states = H.build_all(AWORSet, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(AWORSet, states)
      assert H.queries_of(AWORSet, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: H.max_runs()) do
      final = AWORSet |> H.run(@ids, script) |> then(&H.mesh(AWORSet, &1, @ids))
      assert H.converged_queries(AWORSet, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "concurrent add wins over remove" do
    check all({v, w} <- distinct_pair_gen(), max_runs: H.max_runs()) do
      x = AWORSet.new("x")
      {x, _} = AWORSet.add(x, v)
      {x, _} = AWORSet.remove(x, v)

      y = AWORSet.new("y")
      {y, _} = AWORSet.add(y, w)
      {y, _} = AWORSet.add(y, v)

      merged = AWORSet.join(x, y)

      assert AWORSet.read(merged) == MapSet.new([v, w])
      assert AWORSet.read(AWORSet.join(merged, x)) == AWORSet.read(AWORSet.join(merged, y))
    end
  end

  property "every visible element was added at least once" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: H.max_runs()) do
      added =
        Enum.reduce(ops, MapSet.new(), fn
          {:mutate, _id, :add, [v]}, acc -> MapSet.put(acc, v)
          _, acc -> acc
        end)

      final = ops |> then(&H.run(AWORSet, @ids, &1)) |> then(&H.mesh(AWORSet, &1, @ids))

      assert Enum.all?(H.converged_queries(AWORSet, final), &MapSet.subset?(&1, added))
    end
  end
end
