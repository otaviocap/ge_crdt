ExUnit.start()

defmodule GeCrdt.PropertyHelpers do
  @moduledoc false

  import StreamData

  @spec new(module(), term()) :: term()
  def new(mod, id) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :new, 1) do
      mod.new(id)
    else
      mod.new()
    end
  end

  @spec apply_op(module(), term(), {atom(), [term()]}) :: {term(), term()}
  def apply_op(mod, state, {fun, args}) do
    case apply(mod, fun, [state | args]) do
      {%{__struct__: mod_struct} = new_state, delta} when mod_struct == mod ->
        {new_state, delta}

      %{__struct__: mod_struct} = new_state when mod_struct == mod ->
        {new_state, new_state}
    end
  end

  @spec query(module(), term()) :: term()
  def query(mod, state), do: GeCrdt.Type.query(mod, state)

  @spec run(module(), [term()], [term()]) :: %{optional(term()) => {term(), term() | nil}}
  def run(mod, ids, script) do
    init = Map.new(ids, fn id -> {id, {new(mod, id), nil}} end)

    Enum.reduce(script, init, fn
      {:mutate, id, fun, args}, acc ->
        {state, buf} = acc[id]
        {new_state, delta} = apply_op(mod, state, {fun, args})
        Map.put(acc, id, {new_state, join_buf(mod, buf, delta)})

      {:sync, from, to}, acc ->
        {_from_state, buf_from} = acc[from]
        {state_to, buf_to} = acc[to]

        if buf_from == nil do
          acc
        else
          Map.put(acc, to, {mod.join(state_to, buf_from), join_buf(mod, buf_to, buf_from)})
        end
    end)
  end

  @spec mesh(module(), map(), [term()]) :: map()
  def mesh(mod, acc, ids) do
    pairs = for from <- ids, to <- ids, from != to, do: {:sync, from, to}

    Enum.reduce(pairs, acc, fn {:sync, from, to}, inner ->
      {_from_state, buf_from} = inner[from]
      {state_to, buf_to} = inner[to]

      if buf_from == nil do
        inner
      else
        Map.put(inner, to, {mod.join(state_to, buf_from), join_buf(mod, buf_to, buf_from)})
      end
    end)
  end

  @spec states(map()) :: %{optional(term()) => term()}
  def states(acc) do
    Map.new(acc, fn {id, {state, _buf}} -> {id, state} end)
  end

  @spec converged_queries(module(), map()) :: [term()]
  def converged_queries(mod, acc) do
    acc
    |> states()
    |> Map.values()
    |> Enum.map(&normalize/1)
    |> Enum.map(&query(mod, &1))
  end

  defp normalize(%{id: _} = state), do: %{state | id: nil}
  defp normalize(state), do: state

  defp join_buf(_mod, nil, delta), do: delta
  defp join_buf(mod, buf, delta), do: mod.join(buf, delta)

  @spec permutation([term()]) :: StreamData.t([term()])
  def permutation(base_ops) do
    n = length(base_ops)

    map(list_of(integer(), min_length: n, max_length: n), fn keys ->
      base_ops |> Enum.zip(keys) |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
    end)
  end

  @spec build_all(module(), [{term(), [{atom(), [term()]}]}]) :: [term()]
  def build_all(mod, id_ops_list) do
    Enum.map(id_ops_list, fn {id, ops} ->
      Enum.reduce(ops, new(mod, id), fn {fun, args}, st ->
        elem(apply_op(mod, st, {fun, args}), 0)
      end)
    end)
  end

  @spec merge_all(module(), [term()]) :: [term()]
  def merge_all(mod, states) do
    Enum.map(states, fn st ->
      Enum.reduce(states, st, fn other, acc -> mod.join(acc, other) end)
    end)
  end

  @spec queries_of(module(), [term()]) :: [term()]
  def queries_of(mod, states) do
    Enum.map(states, fn st -> query(mod, normalize(st)) end)
  end

  @spec strip_ids([term()]) :: [{atom(), [term()]}]
  def strip_ids(ops) do
    Enum.map(ops, fn {:mutate, _id, fun, args} -> {fun, args} end)
  end
end
