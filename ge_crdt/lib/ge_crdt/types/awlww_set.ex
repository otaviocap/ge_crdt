defmodule GeCrdt.Types.AWLWWSet do
  @behaviour GeCrdt.Type
  @moduledoc "Add-Wins LWW Set."

  defstruct elements: %{}

  @type timestamp :: integer()
  @type element :: any()
  @type entry :: {timestamp(), boolean()}
  @type t :: %__MODULE__{elements: %{element() => entry()}}

  def new, do: %__MODULE__{}

  def add(%__MODULE__{} = state, value) do
    delta = %__MODULE__{elements: %{value => {get_time(), true}}}

    {join(state, delta), delta}
  end

  def remove(%__MODULE__{} = state, value) do
    delta = %__MODULE__{elements: %{value => {get_time(), false}}}
    {join(state, delta), delta}
  end

  def read(%__MODULE__{elements: elements}) do
    elements
    |> Enum.filter(fn {_elem, {_t, active?}} -> active? end)
    |> Enum.map(fn {elem, _value} -> elem end)
    |> MapSet.new()
  end

  def member?(%__MODULE__{} = state, value) do
    MapSet.member?(read(state), value)
  end

  def join(%__MODULE__{elements: a}, %__MODULE__{elements: b}) do
    merged = Map.merge(a, b, fn _key, val1, val2 -> max_entry(val1, val2) end)

    %__MODULE__{elements: merged}
  end

  @spec max_entry(entry(), entry) :: entry()
  defp max_entry({t1, active1} = e1, {t2, active2} = e2) do
    cond do
      t1 > t2 -> e1
      t2 > t1 -> e2
      true -> {t1, active1 or active2}
    end
  end

  defp get_time(), do: System.system_time()
end
