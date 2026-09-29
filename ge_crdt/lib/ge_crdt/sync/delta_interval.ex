defmodule GeCrdt.Sync.DeltaInterval do
  @moduledoc """
  Default `GeCrdt.Sync` strategy: ship the delta-interval covering
  everything the neighbour has not acknowledged, falling back to the
  full state on gaps, skipping up-to-date neighbours.
  """

  @behaviour GeCrdt.Sync

  @impl true
  def outgoing(%{state: state, seq: seq, buffer: buf, ack: ack} = ctx, _peer) do
    cond do
      ack >= seq ->
        :skip

      buf == %{} ->
        {:full, state, seq}

      Enum.min(Map.keys(buf)) > ack ->
        {:full, state, seq}

      true ->
        deltas =
          buf
          |> Map.keys()
          |> Enum.filter(&(&1 >= ack))
          |> Enum.sort()
          |> Enum.map(&buf[&1])

        case deltas do
          [] ->
            {:full, state, seq}

          [first | rest] ->
            {:delta, Enum.reduce(rest, first, fn a, b -> ctx.module.join(a, b) end), seq}
        end
    end
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
