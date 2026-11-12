defmodule GeCrdt.Types.LexCounter do
  @behaviour GeCrdt.Type
  @moduledoc "Lexicographic counter"

  alias GeCrdt.Utils.Join

  defstruct id: nil, entries: %{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id}

  def increment(target, amount \\ 1)

  def increment(%__MODULE__{id: id, entries: entries} = state, amount) do
    {seq, v} = Map.get(entries, id, {0, 0})
    e = {seq, v + amount}
    {%{state | entries: Map.put(entries, id, e)}, %__MODULE__{entries: %{id => e}}}
  end

  def decrement(target, amount \\ 1)

  def decrement(%__MODULE__{id: id, entries: entries} = state, amount) do
    {seq, v} = Map.get(entries, id, {0, 0})
    e = {seq + 1, v - amount}
    {%{state | entries: Map.put(entries, id, e)}, %__MODULE__{entries: %{id => e}}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      id: a.id || b.id,
      entries: Map.merge(a.entries, b.entries, fn _, l, r -> Join.lex_join(l, r) end)
    }
  end

  def value(%__MODULE__{entries: entries}),
    do: Enum.reduce(entries, 0, fn {_, {_, v}}, acc -> acc + v end)
end
