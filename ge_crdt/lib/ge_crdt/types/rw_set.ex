defmodule GeCrdt.Types.RWSet do
  @behaviour GeCrdt.Type
  @moduledoc """
  Remove-wins set
  """

  alias GeCrdt.Utils.DotKernel

  defstruct id: nil, kernel: %DotKernel{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def add(%__MODULE__{} = state, elem), do: mutate(state, elem, true)

  def remove(%__MODULE__{} = state, elem), do: mutate(state, elem, false)

  def clear(%__MODULE__{kernel: kernel} = state) do
    {kernel_2, delta} = DotKernel.remove_all(kernel)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def reset(%__MODULE__{} = state), do: clear(state)

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: kernel}) do
    flags = kernel |> DotKernel.values() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {e, bools} <- flags, false not in bools, into: MapSet.new(), do: e
  end

  def member?(%__MODULE__{} = state, elem), do: state |> read() |> MapSet.member?(elem)

  defp mutate(%__MODULE__{id: id, kernel: kernel} = state, elem, flag) do
    {kernel_1, delta_t} = DotKernel.remove_value(kernel, {elem, true})
    {kernel_2, delta_f} = DotKernel.remove_value(kernel_1, {elem, false})
    {kernel_3, delta_new} = DotKernel.add(kernel_2, id, {elem, flag})

    delta =
      delta_t
      |> DotKernel.join(delta_f)
      |> DotKernel.join(delta_new)

    {%{state | kernel: kernel_3}, %__MODULE__{kernel: delta}}
  end
end

defimpl GeCrdt.Protocols.Causal, for: GeCrdt.Types.RWSet do
  alias GeCrdt.Utils.DotContext
  alias GeCrdt.Types.RWSet

  def join(%RWSet{} = a, %RWSet{} = b), do: RWSet.join(a, b)

  def reset(%RWSet{} = s), do: RWSet.reset(s)

  def read(%RWSet{} = s), do: RWSet.read(s)

  def context(%RWSet{kernel: kernel}), do: kernel.context

  def adopt(%RWSet{kernel: k} = s, id, ctx) do
    %{s | id: id, kernel: %{k | context: DotContext.join(k.context, ctx)}}
  end

  def empty?(%RWSet{kernel: k}), do: map_size(k.dot_store) == 0
end
