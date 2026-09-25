defmodule GeCrdt.Types.PNCounter do
  @behaviour GeCrdt.Type
  @moduledoc "PN-counter"
  alias GeCrdt.Types.GCounter

  defstruct id: nil, inc: %GCounter{}, dec: %GCounter{}

  @type t :: %__MODULE__{}
  def new(id \\ nil), do: %__MODULE__{id: id, inc: GCounter.new(id), dec: GCounter.new(id)}

  def increment(target, amount \\ 1)

  def increment(%__MODULE__{} = st, amount) do
    {inc, d} = GCounter.increment(%{st.inc | id: st.id}, amount)
    {%{st | inc: inc}, %__MODULE__{inc: d, dec: GCounter.new()}}
  end

  def decrement(target, amount \\ 1)

  def decrement(%__MODULE__{} = st, amount) do
    {dec, d} = GCounter.increment(%{st.dec | id: st.id}, amount)
    {%{st | dec: dec}, %__MODULE__{dec: d, inc: GCounter.new()}}
  end

  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      id: a.id || b.id,
      inc: GCounter.join(a.inc, b.inc),
      dec: GCounter.join(a.dec, b.dec)
    }
  end

  def value(%__MODULE__{inc: p, dec: n}), do: GCounter.value(p) - GCounter.value(n)

  def local(%__MODULE__{id: id, inc: %GCounter{counts: m1}, dec: %GCounter{counts: m2}}),
    do: Map.get(m1, id, 0) - Map.get(m2, id, 0)
end
