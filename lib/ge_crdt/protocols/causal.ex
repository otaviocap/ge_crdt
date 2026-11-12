defprotocol GeCrdt.Protocols.Causal do
  @moduledoc """
  Contract for CRDTs that can live as values inside a `GeCrdt.Types.ORMap`.
  """

  @doc "Least upper bound of two values of the same type (states or deltas)."
  @spec join(t, t) :: t
  def join(a, b)

  @doc """
  Observed reset. Returns `{emptied, delta}`.

  The delta's context must cover *exactly* the dots that were removed, never
  the inherited/shared context, or the removal bleeds into sibling keys.
  """
  @spec reset(t) :: {t, t}
  def reset(value)

  @doc "True when the value's dot store is empty, so its key counts as absent."
  @spec empty?(t) :: boolean()
  def empty?(value)

  @doc "The causal context carried by the value."
  @spec context(t) :: GeCrdt.Utils.DotContext.t()
  def context(value)

  @doc """
  Adopt the value into a map with replica `id` and shared context:
  stamp a missing id and union the context, so fresh dots stay unique across
  keys.
  """
  @spec adopt(t, term(), GeCrdt.Utils.DotContext.t()) :: t
  def adopt(value, id, ctx)

  @doc "Plain-value view of the state."
  @spec read(t) :: term()
  def read(value)
end
