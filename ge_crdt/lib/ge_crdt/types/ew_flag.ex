defmodule GeCrdt.Types.EWFlag do
  @behaviour GeCrdt.Type
  @moduledoc "Enable-wins flag"

  alias GeCrdt.Utils.DotKernel

  defstruct id: nil, kernel: %DotKernel{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def enable(%__MODULE__{id: id, kernel: kernel} = state) do
    {kernel_1, delta_1} = DotKernel.remove_value(kernel, true)
    {kernel_2, delta_2} = DotKernel.add(kernel_1, id, true)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: DotKernel.join(delta_1, delta_2)}}
  end

  def disable(%__MODULE__{kernel: kernel} = state) do
    {kernel_2, delta} = DotKernel.remove_value(kernel, true)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def reset(%__MODULE__{kernel: kernel} = state) do
    {kernel_2, delta} = DotKernel.remove_all(kernel)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: %{dot_store: dot_store}}), do: map_size(dot_store) > 0
end
