defmodule GeCrdt.Utils.DotKernel do
  @moduledoc """
  Dot kernel

  Based on the DotKernel available in the Delta Enabled CRDTs.

  State: `%{dot_store: %{dot => value}, context: DotContext.t}`.

  All mutators follow the δ-CRDT convention: they inflate the state and
  additionally return a minimal delta (`{new_state, delta}`), where the
  delta is itself a valid kernel state joinable elsewhere.
  """

  alias GeCrdt.Utils.{DotContext, Join}

  @type dot :: DotContext.dot()
  @type t :: %__MODULE__{dot_store: %{optional(dot()) => term()}, context: DotContext.t()}

  defstruct dot_store: %{}, context: %DotContext{}

  @doc "Empty kernel."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Join two kernels."
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    dot_store = merge_dot_store(a, b, false)
    %__MODULE__{dot_store: dot_store, context: DotContext.join(a.context, b.context)}
  end

  @doc """
  Deep join: like `join/2` but concurrent payloads under the same dot
  are merged with `GeCrdt.Utils.Join.join/2`.
  """
  @spec deep_join(t(), t()) :: t()
  def deep_join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      dot_store: merge_dot_store(a, b, true),
      context: DotContext.join(a.context, b.context)
    }
  end

  defp merge_dot_store(a, b, deep?) do
    keys = (Map.keys(a.dot_store) ++ Map.keys(b.dot_store)) |> Enum.uniq() |> Enum.sort()

    Enum.reduce(keys, %{}, fn dot, acc ->
      va = Map.fetch(a.dot_store, dot)
      vb = Map.fetch(b.dot_store, dot)

      case {va, vb} do
        {{:ok, _}, :error} ->
          if DotContext.dot_in?(b.context, dot), do: acc, else: Map.put(acc, dot, elem(va, 1))

        {:error, {:ok, _}} ->
          if DotContext.dot_in?(a.context, dot), do: acc, else: Map.put(acc, dot, elem(vb, 1))

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
    {dot, context} = DotContext.make_dot(kernel.context, id)
    new_k = %{kernel | dot_store: Map.put(kernel.dot_store, dot, value), context: context}

    delta = %__MODULE__{
      dot_store: %{dot => value},
      context: DotContext.insert_dot(DotContext.new(), dot)
    }

    {new_k, delta}
  end

  @doc """
  Remove all entries whose value equals `value`.
  Returns `{new_kernel, delta}`.
  """
  @spec remove_value(t(), term()) :: {t(), t()}
  def remove_value(%__MODULE__{} = kernel, value) do
    {kept, removed} =
      Enum.split_with(kernel.dot_store, fn {_dot, v} -> v != value end)

    context =
      Enum.reduce(removed, DotContext.new(), fn {dot, _}, acc ->
        DotContext.insert_dot(acc, dot, false)
      end)
      |> DotContext.compact()

    {%{kernel | dot_store: Map.new(kept)}, %__MODULE__{dot_store: %{}, context: context}}
  end

  @doc "Remove a single dot. Returns `{new_kernel, delta}`."
  @spec remove_dot(t(), dot()) :: {t(), t()}
  def remove_dot(%__MODULE__{} = kernel, dot) do
    case Map.fetch(kernel.dot_store, dot) do
      {:ok, _} ->
        {%{kernel | dot_store: Map.delete(kernel.dot_store, dot)},
         %__MODULE__{dot_store: %{}, context: DotContext.insert_dot(DotContext.new(), dot)}}

      :error ->
        {kernel, new()}
    end
  end

  @doc "Remove everything. Returns `{new_kernel, delta}`."
  @spec remove_all(t()) :: {t(), t()}
  def remove_all(%__MODULE__{} = kernel) do
    context =
      Enum.reduce(kernel.dot_store, DotContext.new(), fn {dot, _}, acc ->
        DotContext.insert_dot(acc, dot, false)
      end)
      |> DotContext.compact()

    {%{kernel | dot_store: %{}}, %__MODULE__{dot_store: %{}, context: context}}
  end

  @doc "Values in the kernel."
  @spec values(t()) :: [term()]
  def values(%__MODULE__{dot_store: dot_store}), do: Map.values(dot_store)

  @doc "Dots in the kernel."
  @spec dots(t()) :: [dot()]
  def dots(%__MODULE__{dot_store: dot_store}), do: Map.keys(dot_store)
end
