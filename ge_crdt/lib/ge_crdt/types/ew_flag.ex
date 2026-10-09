defmodule GeCrdt.Types.EWFlag do
  @behaviour GeCrdt.Type
  @moduledoc "Enable-wins flag"

  alias GeCrdt.Utils.DotKernel

  defstruct id: nil, kernel: %DotKernel{}

  def new(id \\ nil), do: %__MODULE__{id: id}

  def enable(%__MODULE__{id: id, kernel: k} = st) do
    {k1, d1} = DotKernel.remove_value(k, true)
    {k2, d2} = DotKernel.add(k1, id, true)
    {%{st | kernel: k2}, %__MODULE__{kernel: DotKernel.join(d1, d2)}}
  end

  def disable(%__MODULE__{kernel: k} = st) do
    {k2, d} = DotKernel.remove_value(k, true)
    {%{st | kernel: k2}, %__MODULE__{kernel: d}}
  end

  def reset(%__MODULE__{kernel: k} = st) do
    {k2, d} = DotKernel.remove_all(k)
    {%{st | kernel: k2}, %__MODULE__{kernel: d}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: %{ds: ds}}), do: map_size(ds) > 0
end
