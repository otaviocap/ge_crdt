defmodule GeCrdt.Types.GCounter do
  @behaviour GeCrdt.Type

  @moduledoc "Grow-only counter."

  defstruct id: nil, counts: %{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def increment(target, amount \\ 1)

  def increment(%__MODULE__{id: id, counts: map} = state, amount) do
    v = Map.get(map, id, 0) + amount

    {%{state | counts: Map.put(map, id, v)}, %__MODULE__{counts: %{id => v}}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      id: a.id || b.id,
      counts: Map.merge(a.counts, b.counts, fn _, x, y -> max(x, y) end)
    }
  end

  def value(%__MODULE__{counts: map}), do: Enum.reduce(map, 0, fn {_, v}, acc -> acc + v end)

  def local(%__MODULE__{id: id, counts: map}), do: Map.get(map, id, 0)
end
