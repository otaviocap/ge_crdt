defmodule GeCrdt.Utils.Join do
  @moduledoc """
  Generic join-semilattice helpers
  """

  @doc "Least upper bound of two lattice values."
  @spec join(term(), term()) :: term()
  def join(a, b) when is_number(a) and is_number(b), do: max(a, b)
  def join(%MapSet{} = a, %MapSet{} = b), do: MapSet.union(a, b)

  def join(a, b) when is_map(a) and is_map(b) do
    mod = Map.get(a, :__struct__)

    cond do
      mod != nil and mod == Map.get(b, :__struct__) and joinable?(mod) ->
        apply(mod, :join, [a, b])

      true ->
        Map.merge(a, b, fn _k, x, y -> join(x, y) end)
    end
  end

  def join(a, b) when is_tuple(a) and is_tuple(b) and tuple_size(a) == 2 and tuple_size(b) == 2 do
    {join(elem(a, 0), elem(b, 0)), join(elem(a, 1), elem(b, 1))}
  end

  def join(nil, b), do: b
  def join(a, _b), do: a

  defp joinable?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :join, 2)
  end

  @doc """
  Lexicographic join for `{timestamp, payload}` pairs (remove-wins bias
  on ties goes to the caller; here ties join payloads).
  Based on the `lexjoin` available in the Delta Enabled CRDTs
  """
  @spec lexjoin({term(), term()}, {term(), term()}) :: {term(), term()}
  def lexjoin({t1, _} = l, {t2, _} = r) do
    cond do
      l == r -> l
      t1 > t2 -> l
      t2 > t1 -> r
      true -> {t1, join(elem(l, 1), elem(r, 1))}
    end
  end
end
