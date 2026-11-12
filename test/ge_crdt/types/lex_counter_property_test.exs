defmodule GeCrdt.Types.LexCounterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.LexCounter

  @ids ["a", "b", "c"]

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      bind(member_of([:increment, :decrement]), fn op ->
        map(member_of(1..3), fn n -> {:mutate, id, op, [n]} end)
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

  property "delta decomposition holds for increment and decrement" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:increment, :decrement]),
            n <- member_of(1..3),
            max_runs: H.max_runs()
          ) do
      state = LexCounter |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      {new_state, delta} = apply(LexCounter, op, [state, n])
      assert LexCounter.join(state, delta) == new_state
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
      states = H.build_all(LexCounter, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(LexCounter, states)
      assert H.queries_of(LexCounter, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge after gossiping deltas" do
    check all(script <- script_gen(), max_runs: H.max_runs()) do
      final = LexCounter |> H.run(@ids, script) |> then(&H.mesh(LexCounter, &1, @ids))
      assert H.converged_queries(LexCounter, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "sequential value follows the increment/decrement fold" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: H.max_runs()) do
      mine = Enum.filter(ops, fn {:mutate, id, _op, _args} -> id == "a" end)

      {state, _} =
        Enum.reduce(mine, {LexCounter.new("a"), nil}, fn {:mutate, _id, op, [n]}, {st, _} ->
          {new_state, _} = apply(LexCounter, op, [st, n])
          {new_state, nil}
        end)

      expected =
        Enum.reduce(mine, 0, fn
          {:mutate, _id, :increment, [n]}, acc -> acc + n
          {:mutate, _id, :decrement, [n]}, acc -> acc - n
        end)

      assert LexCounter.value(state) == expected
    end
  end
end
