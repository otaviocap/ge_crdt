defmodule GeCrdt.Types.ORMapPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GeCrdt.PropertyHelpers, as: H
  alias GeCrdt.Types.{AWORSet, ORMap}

  @ids ["a", "b", "c"]
  @keys ["k1", "k2"]

  defp add_fun(v), do: fn s -> AWORSet.add(s, v) end
  defp rmv_fun(v), do: fn s -> AWORSet.remove(s, v) end

  defp mutate_gen do
    bind(member_of(@ids), fn id ->
      one_of([
        bind(member_of(@keys), fn k ->
          map(member_of(0..3), fn v -> {:mutate, id, :update, [k, AWORSet.new(), add_fun(v)]} end)
        end),
        bind(member_of(@keys), fn k ->
          map(member_of(0..3), fn v -> {:mutate, id, :update, [k, AWORSet.new(), rmv_fun(v)]} end)
        end),
        map(member_of(@keys), fn k -> {:mutate, id, :delete, [k]} end),
        constant({:mutate, id, :clear, []})
      ])
    end)
  end

  defp script_gen do
    sync_gen =
      bind(member_of(@ids), fn from ->
        map(member_of(@ids), fn to -> {:sync, from, to} end)
      end)

    list_of(one_of([mutate_gen(), sync_gen]), max_length: 12)
  end

  property "delta decomposition holds for delete and clear" do
    check all(
            prefix <- list_of(mutate_gen(), max_length: 5),
            op <- member_of([:delete, :clear]),
            k <- member_of(@keys),
            max_runs: H.max_runs()
          ) do
      state = ORMap |> H.run(@ids, prefix) |> H.states() |> Map.fetch!("a")
      args = if op == :clear, do: [], else: [k]
      {new_state, delta} = apply(ORMap, op, [state | args])
      assert ORMap.join(state, delta) == new_state
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
      states = H.build_all(ORMap, [{"p1", ops}, {"p2", perm_a}, {"p3", perm_b}])
      merged = H.merge_all(ORMap, states)
      assert H.queries_of(ORMap, merged) |> Enum.uniq() |> length() == 1
    end
  end

  property "replicas converge on the same nested contents" do
    check all(script <- script_gen(), max_runs: H.max_runs()) do
      final = ORMap |> H.run(@ids, script) |> then(&H.mesh(ORMap, &1, @ids))
      assert H.converged_queries(ORMap, final) |> Enum.uniq() |> length() == 1
    end
  end

  property "every surviving key was added at least once" do
    check all(ops <- list_of(mutate_gen(), max_length: 10), max_runs: H.max_runs()) do
      added =
        Enum.reduce(ops, MapSet.new(), fn
          {:mutate, _id, :update, [k, _default, _fun]}, acc -> MapSet.put(acc, k)
          _, acc -> acc
        end)

      final =
        ORMap |> H.run(@ids, ops) |> then(&H.mesh(ORMap, &1, @ids)) |> H.states() |> Map.values()

      assert Enum.all?(final, fn st ->
               Map.keys(st.entries) |> MapSet.new() |> MapSet.subset?(added)
             end)
    end
  end
end
