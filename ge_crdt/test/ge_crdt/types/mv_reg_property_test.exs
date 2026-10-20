defmodule GeCrdt.Types.MVRegPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.MVReg

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      map(member_of(0..3), fn v -> {:mutate, id, :write, [v]} end)
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for write and resolve" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:write, :resolve]),
            v <- member_of(0..3),
            max_runs: 40
          ) do
      state = MVReg |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      args = if op == :resolve, do: [], else: [v]
      {new_state, delta} = apply(MVReg, op, [state | args])
      assert MVReg.join(state, delta) == new_state
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
      states = H.build_all(MVReg, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(MVReg, states)
      assert H.queries_of(MVReg, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge on the same sibling set" do
    check all(script <- script_gen(), max_runs: 40) do
      final = MVReg |> H.run(@ids, script) |> then(&H.mesh(MVReg, &1, @ids))
      assert H.converged_queries(MVReg, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "sequential writes keep only the last value" do
    check all(writes <- list_of(member_of(0..3), min_length: 1, max_length: 6), max_runs: 40) do
      state = Enum.reduce(writes, MVReg.new("a"), fn v, st -> elem(MVReg.write(st, v), 0) end)
      assert MVReg.read(state) == MapSet.new([List.last(writes)])
    end
  end

  property "resolve collapses siblings to their maximum" do
    check all(ops <- list_of(mutate_gen(), max_length: 8), max_runs: 40) do
      meshed = ops |> then(&H.run(MVReg, @ids, &1)) |> then(&H.mesh(MVReg, &1, @ids))
      state = meshed |> H.states() |> Map.fetch!("a")
      before = MVReg.read(state)
      {resolved, _} = MVReg.resolve(state)

      if before == MapSet.new() do
        assert MVReg.read(resolved) == MapSet.new()
      else
        assert MVReg.read(resolved) == MapSet.new([Enum.max(before)])
      end
    end
  end
end
