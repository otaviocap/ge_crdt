defmodule GeCrdt.Types.AWSet do
  @behaviour GeCrdt.Type
  @moduledoc """
  Add-wins set.
  """
  alias GeCrdt.Utils.DotKernel
  defstruct id: nil, kernel: %DotKernel{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def add(%__MODULE__{id: id, kernel: k} = state, value) do
    {k1, d1} = DotKernel.remove_value(k, value)
    {k2, d2} = DotKernel.add(k1, id, value)

    {%{state | kernel: k2}, %__MODULE__{kernel: DotKernel.join(d1, d2)}}
  end

  def remove(%__MODULE__{kernel: k} = state, value) do
    {k2, d} = DotKernel.remove_value(k, value)
    {%{state | kernel: k2}, %__MODULE__{kernel: d}}
  end

  def reset(%__MODULE__{kernel: k} = state) do
    {k2, d} = DotKernel.remove_all(k)
    {%{state | kernel: k2}, %__MODULE__{kernel: d}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: k}), do: k |> DotKernel.values() |> MapSet.new()

  def member?(%__MODULE__{} = state, value), do: state |> read() |> MapSet.member?(value)

  def context(%__MODULE__{kernel: k}), do: k.context
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
