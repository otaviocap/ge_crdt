defmodule GeCrdt.Sync.FullState do
  @moduledoc """
  `GeCrdt.Sync` strategy that always ships the full state
  while still honouring acks, so up-to-date neighbours are
  skipped exactly like with delta-intervals. Useful when
  deltas are not worth tracking, or as a baseline.
  """

  @behaviour GeCrdt.Sync

  @impl true
  def outgoing(%{state: state, seq: seq, ack: ack}, _peer) do
    if ack >= seq, do: :skip, else: {:full, state, seq}
  end

  @impl true
  def deliver(peer, message) do
    try do
      send(peer, message)
      :ok
    rescue
      ArgumentError -> :ok
    end
  end
end
