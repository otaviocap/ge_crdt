defmodule GeCrdt.Types.AWSet do
  @behaviour GeCrdt.Type
  @moduledoc """
  Add-wins set.
  """

  alias GeCrdt.Utils.DotKernel

  defstruct id: nil, kernel: %DotKernel{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def add(%__MODULE__{id: id, kernel: kernel} = state, elem) do
    {kernel_1, delta_1} = DotKernel.remove_value(kernel, elem)
    {kernel_2, delta_2} = DotKernel.add(kernel_1, id, elem)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: DotKernel.join(delta_1, delta_2)}}
  end

  def remove(%__MODULE__{kernel: kernel} = state, elem) do
    {kernel_2, delta} = DotKernel.remove_value(kernel, elem)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def clear(%__MODULE__{kernel: kernel} = state) do
    {kernel_2, delta} = DotKernel.remove_all(kernel)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def reset(%__MODULE__{} = state), do: clear(state)

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: kernel}), do: kernel |> DotKernel.values() |> MapSet.new()

  def member?(%__MODULE__{} = state, elem), do: state |> read() |> MapSet.member?(elem)
end

defimpl GeCrdt.Protocols.Causal, for: GeCrdt.Types.AWSet do
  alias GeCrdt.Utils.DotContext
  alias GeCrdt.Types.AWSet

  def join(%AWSet{} = a, %AWSet{} = b), do: AWSet.join(a, b)

  def reset(%AWSet{} = s), do: AWSet.reset(s)

  def read(%AWSet{} = s), do: AWSet.read(s)

  def context(%AWSet{kernel: kernel}), do: kernel.context

  def adopt(%AWSet{kernel: k} = s, id, ctx) do
    %{s | id: id, kernel: %{k | context: DotContext.join(k.context, ctx)}}
  end

  def empty?(%AWSet{kernel: k}), do: map_size(k.dot_store) == 0
end
