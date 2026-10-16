defmodule GeCrdt.Types.ORMap do
  @behaviour GeCrdt.Type

  @moduledoc """
  Observed-remove map of keys to causal CRDTs.

  Values can be any type implementing `GeCrdt.Causal`.
  """

  alias GeCrdt.Protocols.Causal
  alias GeCrdt.Utils.DotContext

  defstruct id: nil, entries: %{}, ctx: %DotContext{}

  @type key :: term()
  @type t :: %__MODULE__{
          id: term(),
          entries: %{optional(key) => struct()},
          ctx: DotContext.t()
        }

  def new(id \\ nil), do: %__MODULE__{id: id}

  @spec fetch(t, key) :: {:ok, struct()} | :error
  def fetch(%__MODULE__{entries: m}, key) do
    with {:ok, v} <- Map.fetch(m, key),
         false <- Causal.empty?(v) do
      {:ok, v}
    else
      _ -> :error
    end
  end

  @spec get(t, key, term()) :: struct() | term()
  def get(%__MODULE__{} = map, key, default \\ nil) do
    case fetch(map, key) do
      {:ok, v} -> v
      :error -> default
    end
  end

  @spec has_key?(t, key) :: boolean()
  def has_key?(%__MODULE__{} = map, key), do: match?({:ok, _}, fetch(map, key))

  @spec keys(t) :: [key]
  def keys(%__MODULE__{} = map), do: map |> to_map() |> Map.keys()

  @spec to_map(t) :: %{optional(key) => struct()}
  def to_map(%__MODULE__{entries: m}) do
    for {k, v} <- m, not Causal.empty?(v), into: %{}, do: {k, v}
  end

  @spec read(t) :: %{optional(key) => term()}
  def read(%__MODULE__{entries: m}) do
    for {k, v} <- m, not Causal.empty?(v), into: %{}, do: {k, Causal.read(v)}
  end

  @spec context(t) :: DotContext.t()
  def context(%__MODULE__{ctx: c}), do: c

  @spec update(t, key, struct(), (struct() -> {struct(), struct()})) :: {t, t}
  def update(%__MODULE__{id: id, entries: m, ctx: c} = st, key, default, fun)
      when is_function(fun, 1) do
    cur = m |> Map.get(key, default) |> Causal.adopt(id, c)
    {_updated, delta} = fun.(cur)

    apply_delta(st, key, delta)
  end

  @spec delete(t, key) :: {t, t}
  def delete(%__MODULE__{entries: m} = st, key) do
    case m do
      %{^key => v} ->
        {_emptied, delta} = Causal.reset(v)
        apply_delta(st, key, delta)

      _ ->
        {st, %__MODULE__{}}
    end
  end

  @doc "Erases every key. Returns `{map, delta}`."
  @spec clear(t) :: {t, t}
  def clear(%__MODULE__{entries: m} = st) do
    Enum.reduce(Map.keys(m), {st, %__MODULE__{}}, fn key, {state, delta} ->
      {state2, delta2} = delete(state, key)
      {state2, join(delta, delta2)}
    end)
  end

  @spec join(t, t) :: t
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      id: a.id,
      entries: Map.merge(a.entries, b.entries, fn _k, x, y -> Causal.join(x, y) end),
      ctx: DotContext.join(a.ctx, b.ctx)
    }
  end

  defp apply_delta(%__MODULE__{} = st, key, delta) do
    delta_map = %__MODULE__{entries: %{key => delta}, ctx: Causal.context(delta)}
    {join(st, delta_map), delta_map}
  end
end

defimpl GeCrdt.Protocols.Causal, for: GeCrdt.Types.ORMap do
  alias GeCrdt.Protocols.Causal
  alias GeCrdt.Types.ORMap
  alias GeCrdt.Utils.DotContext

  def join(%ORMap{} = a, %ORMap{} = b), do: ORMap.join(a, b)

  def reset(%ORMap{} = m), do: ORMap.clear(m)

  def read(%ORMap{} = m), do: ORMap.read(m)

  def context(%ORMap{ctx: c}), do: c

  def adopt(%ORMap{id: nil} = m, id, ctx) when id != nil do
    adopt(%{m | id: id}, id, ctx)
  end

  def adopt(%ORMap{ctx: c} = m, _id, ctx), do: %{m | ctx: DotContext.join(c, ctx)}

  def empty?(%ORMap{entries: e}) do
    Enum.all?(e, fn {_k, v} -> Causal.empty?(v) end)
  end
end
