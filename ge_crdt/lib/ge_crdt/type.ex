defmodule GeCrdt.Type do
  @doc "Creates a new instance of the type"
  @callback new() :: term()

  @doc "Least upper bound of two states or deltas."
  @callback join(term(), term()) :: term()

  @doc "Query the state."
  @callback read(term()) :: term()

  @doc "Query the state."
  @callback value(term()) :: term()

  @optional_callbacks read: 1, value: 1
end
