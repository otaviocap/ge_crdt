defmodule GeCrdt.Types.RWSetPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.RWSet

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
      state = RWSet |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      args = if op == :reset, do: [], else: [v]
      {new_state, delta} = apply(RWSet, op, [state | args])
      assert RWSet.join(state, delta) == new_state
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
      states = H.build_all(RWSet, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(RWSet, states)
      assert H.queries_of(RWSet, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: H.max_runs()) do
      final = RWSet |> H.run(@ids, script) |> then(&H.mesh(RWSet, &1, @ids))
      assert H.converged_queries(RWSet, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "concurrent remove wins over add" do
    check all({v, w} <- distinct_pair_gen(), max_runs: H.max_runs()) do
      x = RWSet.new("x")
      {x, _} = RWSet.add(x, v)
      {x, _} = RWSet.remove(x, v)

      y = RWSet.new("y")
      {y, _} = RWSet.add(y, w)
      {y, _} = RWSet.add(y, v)

      merged = RWSet.join(x, y)

      assert RWSet.read(merged) == MapSet.new([w])
      assert RWSet.read(RWSet.join(merged, x)) == RWSet.read(RWSet.join(merged, y))
    end
  end

  property "observed remove-then-add resurrects, add-then-remove hides" do
    check all(v <- member_of(0..4), max_runs: H.max_runs()) do
      s = RWSet.new("a")
      {s, _} = RWSet.add(s, v)
      {s, _} = RWSet.remove(s, v)
      refute RWSet.member?(s, v)

      {s, _} = RWSet.add(s, v)
      assert RWSet.member?(s, v)
    end
  end
end
