defmodule GeCrdt.Types.TwoPSet do
  @behaviour GeCrdt.Type
  @moduledoc "Two-phase set."

  defstruct adds: MapSet.new(), rems: MapSet.new()

  @type t :: %__MODULE__{}
  def new, do: %__MODULE__{}

  def add(%__MODULE__{adds: adds, rems: rems} = state, value) do
    if MapSet.member?(rems, value),
      do: {state, new()},
      else: {%{state | adds: MapSet.put(adds, value)}, %__MODULE__{adds: MapSet.new([value])}}
  end

  def remove(%__MODULE__{adds: adds, rems: rems} = state, value) do
    {%{state | adds: MapSet.delete(adds, value), rems: MapSet.put(rems, value)},
     %__MODULE__{rems: MapSet.new([value])}}
  end

  def reset(%__MODULE__{adds: adds} = state) do
    {%{state | adds: MapSet.new(), rems: MapSet.union(state.rems, adds)}, %__MODULE__{rems: adds}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    rems_union = MapSet.union(a.rems, b.rems)
    adds_union = MapSet.union(a.adds, b.adds) |> MapSet.difference(rems_union)
    %__MODULE__{adds: adds_union, rems: rems_union}
  end

  def read(%__MODULE__{adds: adds}), do: adds

  def member?(%__MODULE__{adds: adds}, value), do: MapSet.member?(adds, value)
end
