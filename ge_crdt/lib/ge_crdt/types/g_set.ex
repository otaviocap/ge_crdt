defmodule GeCrdt.Types.GSet do
  @behaviour GeCrdt.Type
  @moduledoc "Grow-only set."

  defstruct elements: MapSet.new()

  @type t :: %__MODULE__{elements: MapSet.t()}
  def new, do: %__MODULE__{}

  def add(%__MODULE__{elements: s} = state, v) do
    {%{state | elements: MapSet.put(s, v)}, %__MODULE__{elements: MapSet.new([v])}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b),
    do: %__MODULE__{elements: MapSet.union(a.elements, b.elements)}

  def read(%__MODULE__{elements: s}), do: s

  def member?(%__MODULE__{elements: s}, v), do: MapSet.member?(s, v)
end
