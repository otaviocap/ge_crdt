defmodule GeCrdt.Sync do
  @moduledoc """
  Behaviour for gossip-round dissemination strategies

  A strategy decides, per neighbour, what to send this round, and how
  to deliver it. It receives the replica bookkeeping:

  - `:module`, the `GeCrdt.Type` implementation;
  - `:state`, the current CRDT state;
  - `:seq`, the next sequence number/
  - `:buffer`, `%{seq_number => delta}`;
  - `:ack`, the neighbour's last acknowledged sequence number.

  It answers with one decision (where `n` is the sender sequence the
  payload covers through, echoed back in the receiver's ack):

  - `:skip`, the neighbour is up to date, send nothing;
  - `{:delta, payload, n}`, send the delta-interval;
  - `{:full, state, n}`, fall back to the full state (new members,
    collected history).
  """

  @type bookkeeping :: %{
          required(:module) => module(),
          required(:state) => term(),
          required(:seq) => non_neg_integer(),
          required(:buffer) => %{optional(non_neg_integer()) => term()},
          required(:ack) => non_neg_integer()
        }

  @type decision ::
          :skip
          | {:delta, term(), non_neg_integer()}
          | {:full, term(), non_neg_integer()}

  @doc "Decide what to send one neighbour this round."
  @callback outgoing(bookkeeping(), peer :: pid()) :: decision()

  @doc "Deliver an already-wrapped `{:ge_crdt_delta, ...}` message."
  @callback deliver(peer :: pid(), message :: term()) :: :ok
end
