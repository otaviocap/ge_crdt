defmodule GeCrdt.Utils.DotKernel do
  @moduledoc """
  Dot kernel

  Based on the DotKernel available in the Delta Enabled CRDTs.

  State: `%{ds: %{dot => value}, ctx: CausalContext.t}`.

  All mutators follow the δ-CRDT convention: they inflate the state and
  additionally return a minimal delta (`{new_state, delta}`), where the
  delta is itself a valid kernel state joinable elsewhere.
  """

  alias GeCrdt.Utils.{DotContext, Join}

  @type dot :: DotContext.dot()
  @type t :: %__MODULE__{ds: %{optional(dot()) => term()}, ctx: DotContext.t()}

  defstruct ds: %{}, ctx: %DotContext{}

  @doc "Empty kernel."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Join two kernels."
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    ds = merge_ds(a, b, false)
    %__MODULE__{ds: ds, ctx: DotContext.join(a.ctx, b.ctx)}
  end

  @doc """
  Deep join: like `join/2` but concurrent payloads under the same dot
  are merged with `GeCrdt.Utils.Join.join/2`.
  """
  @spec deep_join(t(), t()) :: t()
  def deep_join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{ds: merge_ds(a, b, true), ctx: DotContext.join(a.ctx, b.ctx)}
  end

  defp merge_ds(a, b, deep?) do
    keys = (Map.keys(a.ds) ++ Map.keys(b.ds)) |> Enum.uniq() |> Enum.sort()

    Enum.reduce(keys, %{}, fn dot, acc ->
      va = Map.fetch(a.ds, dot)
      vb = Map.fetch(b.ds, dot)

      case {va, vb} do
        {{:ok, _}, :error} ->
          if DotContext.dot_in?(b.ctx, dot), do: acc, else: Map.put(acc, dot, elem(va, 1))

        {:error, {:ok, _}} ->
          if DotContext.dot_in?(a.ctx, dot), do: acc, else: Map.put(acc, dot, elem(vb, 1))

        {{:ok, x}, {:ok, _y}} ->
          if deep? and x != elem(vb, 1) do
            Map.put(acc, dot, Join.join(x, elem(vb, 1)))
          else
            Map.put(acc, dot, x)
          end

        _ ->
          acc
      end
    end)
  end

  @doc """
  Add `value` under a fresh dot for `id`.
  Returns `{new_kernel, delta}`.
  """
  @spec add(t(), term(), term()) :: {t(), t()}
  def add(%__MODULE__{} = kernel, id, value) do
    {dot, ctx} = DotContext.make_dot(kernel.ctx, id)
    new_k = %{kernel | ds: Map.put(kernel.ds, dot, value), ctx: ctx}
    delta = %__MODULE__{ds: %{dot => value}, ctx: DotContext.insert_dot(DotContext.new(), dot)}
    {new_k, delta}
  end

  @doc """
  Remove all entries whose value equals `value`.
  Returns `{new_kernel, delta}`.
  """
  @spec remove_value(t(), term()) :: {t(), t()}
  def remove_value(%__MODULE__{} = kernel, value) do
    {kept, removed} =
      Enum.split_with(kernel.ds, fn {_dot, v} -> v != value end)

    ctx =
      Enum.reduce(removed, DotContext.new(), fn {dot, _}, acc ->
        DotContext.insert_dot(acc, dot, false)
      end)
      |> DotContext.compact()

    {%{kernel | ds: Map.new(kept)}, %__MODULE__{ds: %{}, ctx: ctx}}
  end

  @doc "Remove a single dot. Returns `{new_kernel, delta}`."
  @spec remove_dot(t(), dot()) :: {t(), t()}
  def remove_dot(%__MODULE__{} = kernel, dot) do
    case Map.fetch(kernel.ds, dot) do
      {:ok, _} ->
        {%{kernel | ds: Map.delete(kernel.ds, dot)},
         %__MODULE__{ds: %{}, ctx: DotContext.insert_dot(DotContext.new(), dot)}}

      :error ->
        {kernel, new()}
    end
  end

  @doc "Remove everything. Returns `{new_kernel, delta}`."
  @spec remove_all(t()) :: {t(), t()}
  def remove_all(%__MODULE__{} = kernel) do
    ctx =
      Enum.reduce(kernel.ds, DotContext.new(), fn {dot, _}, acc ->
        DotContext.insert_dot(acc, dot, false)
      end)
      |> DotContext.compact()

    {%{kernel | ds: %{}}, %__MODULE__{ds: %{}, ctx: ctx}}
  end

  @doc "Values in the kernel."
  @spec values(t()) :: [term()]
  def values(%__MODULE__{ds: ds}), do: Map.values(ds)

  @doc "Dots in the kernel."
  @spec dots(t()) :: [dot()]
  def dots(%__MODULE__{ds: ds}), do: Map.keys(ds)
end
