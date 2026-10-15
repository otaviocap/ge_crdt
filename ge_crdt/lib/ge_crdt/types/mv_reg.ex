defmodule GeCrdt.Types.MVReg do
  @behaviour GeCrdt.Type
  @moduledoc "Optimized multi-value register."

  alias GeCrdt.Utils.{DotKernel, Join}

  defstruct id: nil, kernel: %DotKernel{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def write(%__MODULE__{id: id, kernel: kernel} = state, val) do
    {kernel_1, delta_1} = DotKernel.remove_all(kernel)
    {kernel_2, delta_2} = DotKernel.add(kernel_1, id, val)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: DotKernel.join(delta_1, delta_2)}}
  end

  def reset(%__MODULE__{kernel: kernel} = state) do
    {kernel_2, delta} = DotKernel.remove_all(kernel)
    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  @doc "Keep only maximal siblings under value join order. Code based on the cpp implementation"
  def resolve(%__MODULE__{kernel: kernel} = state) do
    vals = kernel |> DotKernel.values() |> Enum.uniq()
    dominated = for a <- vals, b <- vals, a != b, Join.join(a, b) == b, do: a

    {kernel_2, delta} =
      Enum.reduce(Enum.uniq(dominated), {kernel, DotKernel.new()}, fn v, {kk, dd} ->
        {kk2, delta_2} = DotKernel.remove_value(kk, v)
        {kk2, DotKernel.join(dd, delta_2)}
      end)

    {%{state | kernel: kernel_2}, %__MODULE__{kernel: delta}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{id: a.id || b.id, kernel: DotKernel.join(a.kernel, b.kernel)}
  end

  def read(%__MODULE__{kernel: kernel}), do: kernel |> DotKernel.values() |> MapSet.new()
end
