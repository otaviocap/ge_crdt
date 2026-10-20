defmodule GeCrdt.Types.EWFlagPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.EWFlag

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      map(member_of([:enable, :disable]), fn op -> {:mutate, id, op, []} end)
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for enable, disable and reset" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:enable, :disable, :reset]),
            max_runs: 40
          ) do
      state = EWFlag |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      {new_state, delta} = apply(EWFlag, op, [state])
      assert EWFlag.join(state, delta) == new_state
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
      states = H.build_all(EWFlag, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(EWFlag, states)
      assert H.queries_of(EWFlag, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: 40) do
      final = EWFlag |> H.run(@ids, script) |> then(&H.mesh(EWFlag, &1, @ids))
      assert H.converged_queries(EWFlag, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "sequential read reflects the last operation" do
    check all(ops <- list_of(member_of([:enable, :disable]), max_length: 8), max_runs: 40) do
      state = Enum.reduce(ops, EWFlag.new("a"), fn op, st -> elem(apply(EWFlag, op, [st]), 0) end)
      expected = ops != [] and List.last(ops) == :enable
      assert EWFlag.read(state) == expected
    end
  end
end
