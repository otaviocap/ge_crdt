defmodule GeCrdt.Type do
  alias GeCrdt.Utils.{DotContext, DotKernel}

  @doc "Creates a new instance of the type"
  @callback new() :: term()

  @doc "Least upper bound of two states or deltas."
  @callback join(term(), term()) :: term()

  @doc "Query the state."
  @callback read(term()) :: term()

  @doc "Query the state."
  @callback value(term()) :: term()

  @optional_callbacks read: 1, value: 1

  @doc """
  Build a bottom state, binding `id` when the type supports `new/1`.
  """
  @spec new(module(), term()) :: term()
  def new(mod, id) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :new, 1) do
      mod.new(id)
    else
      mod.new()
    end
  end

  @doc """
  Run a type's query without knowing whether it calls it `read/1`
  or `value/1`. Falls back to the raw state.
  """
  @spec query(module(), term()) :: term()
  def query(mod, state) do
    loaded? = Code.ensure_loaded?(mod)

    cond do
      loaded? and function_exported?(mod, :read, 1) -> mod.read(state)
      loaded? and function_exported?(mod, :value, 1) -> mod.value(state)
      true -> state
    end
  end

  @doc """
  Run a mutator `op` with `args` against `state` and return the
  resulting delta.
  """
  @spec apply_mutation(module(), term(), atom(), [term()]) :: term()
  def apply_mutation(mod, state, op, args) do
    case apply(mod, op, [state | args]) do
      {%{__struct__: ^mod}, %{__struct__: ^mod} = delta} -> delta
      %{__struct__: ^mod} = new_state -> new_state
    end
  end

  @doc """
  Causal context carried by any dot-kernel-based value.
  """
  @spec causal_context(term()) :: DotContext.t()
  def causal_context(v) do
    cond do
      match?(%DotKernel{}, v) -> v.ctx
      match?(%{kernel: %DotKernel{}}, v) -> v.kernel.ctx
      match?(%{ctx: %DotContext{}}, v) -> v.ctx
      true -> DotContext.new()
    end
  end

  @doc """
  Adopt a nested value into a map with replica `id` and shared context
  `ctx`: stamp a missing replica id (so future dots are namespaced,
  never `nil`) and union dot-bearing contexts (so fresh dots stay
  unique). Dotless values pass through untouched. Deterministic, so all
  replicas agree.
  """
  @spec adopt(term(), term(), DotContext.t()) :: term()
  def adopt(%{id: nil} = v, id, ctx) when is_struct(v) and id != nil do
    %{v | id: id} |> seed(ctx)
  end

  def adopt(v, _id, ctx), do: seed(v, ctx)

  defp seed(%{kernel: %{ctx: _} = k} = v, ctx) when is_struct(v) do
    %{v | kernel: %{k | ctx: DotContext.join(k.ctx, ctx)}}
  end

  defp seed(%{bag: %{kernel: %{ctx: _} = k} = b} = v, ctx) when is_struct(v) do
    %{v | bag: %{b | kernel: %{k | ctx: DotContext.join(k.ctx, ctx)}}}
  end

  defp seed(%{ctx: _} = v, ctx) when is_struct(v) do
    %{v | ctx: DotContext.join(v.ctx, ctx)}
  end

  defp seed(v, _ctx), do: v
end
