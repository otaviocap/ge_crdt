defmodule GeCrdt.AntiEntropy.Causal do
  @moduledoc """
  Delta-interval anti-entropy (based on Algorithm 2 from Almeida et al.,
  "Efficient State-based CRDTs by Delta-Mutation").

  Each process holds one replica: the CRDT state, a durable-style
  sequence counter, a volatile buffer of sequenced deltas and a
  per-neighbour acknowledgment map. Periodically (or on demand via
  `sync/1`) every neighbour is sent either the delta-interval
   covering everything it has not yet acknowledged, or, when
  there is a gap (e.g. history was garbage-collected or the neighbour is
  new), the full state. Receivers join what they do not already know
  while joining every delta everywhere still guarantees convergence.

  What to send each round is decided by a `GeCrdt.Sync` strategy
  (`:sync` option, default `GeCrdt.Sync.DeltaInterval`).

  Differences from the paper's sketch, all behaviour-preserving:
  - instead of picking one random neighbour per tick, every neighbour
    with unacknowledged deltas is sent to;
  - neighbours that already acknowledged everything are skipped;
  - an `epoch` (fresh per process start) tags outgoing deltas and is
    echoed in acks, so a delayed ack from before a restart can never
    mark post-restart deltas as delivered;
  - the state is kept in memory; a restarted replica simply
    falls back to full-state transfer, as the paper prescribes.
  """

  @behaviour GeCrdt.AntiEntropy

  use GenServer

  alias GeCrdt.{Discovery, Sync, Type}

  @type server :: GenServer.server()

  defstruct crdt_module: nil,
            replica_id: nil,
            crdt_state: nil,
            sync_interval: 100,
            sync_on_mutate: true,
            sync_strategy: Sync.DeltaInterval,
            neighbours: [],
            discovery: nil,
            seq: 0,
            buffer: %{},
            acks: %{},
            epoch: nil

  @doc """
  Start a replica of `crdt_module` identified by `replica_id`.

  Options:

  - `:neighbours`, list of neighbour pids (default `[]`);
  - `:sync_interval`, milliseconds between gossip rounds, or `:manual`
    to only sync on `sync/1` (default `100`);
  - `:sync_on_mutate`, gossip a round right after every local `mutate/3`
    so the new delta starts travelling immediately (default `true`).
    Set to `false` for strict batching, where deltas only ship on the
    periodic tick / `sync/1` and collapse into fewer, denser intervals;
  - `:sync`, `GeCrdt.Sync` strategy module deciding per-round payloads
    (default `GeCrdt.Sync.DeltaInterval`);
  - `:discovery`, `true` or `[scope: scope, group: group]` to
    auto-discover neighbours through a `:pg` process group; a bare term
    (e.g. `:my_group`) is used as the group name;
  - `:group`, connect to a named `:pg` group instead of the default group
    named after the CRDT module (enables discovery);
  - `:name`, `GenServer` name registration.
  """
  @spec start_link(module(), term(), keyword()) :: GenServer.on_start()
  @impl GeCrdt.AntiEntropy
  def start_link(crdt_module, replica_id, opts \\ []) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, {crdt_module, replica_id, opts}, gen_opts)
  end

  @doc "Replace the neighbour set (prunes acks of removed neighbours)."
  @spec set_neighbours(server(), [pid()]) :: :ok
  @impl GeCrdt.AntiEntropy
  def set_neighbours(server, neighbours) do
    GenServer.call(server, {:set_neighbours, neighbours})
  end

  @doc """
  Apply `op` with `args` to the local state.

  Invokes the type's mutator, joins the resulting delta locally and
  buffers it for future gossip rounds.
  """
  @spec mutate(server(), atom(), [term()]) :: :ok
  @impl GeCrdt.AntiEntropy
  def mutate(server, op, args \\ []) do
    GenServer.call(server, {:mutate, op, args})
  end

  @doc """
  Run the type's query against the local state (`read/1` when exported,
  otherwise `value/1`).
  """
  @spec read(server()) :: term()
  @impl GeCrdt.AntiEntropy
  def read(server) do
    GenServer.call(server, :read)
  end

  @doc "Return the raw CRDT state (useful in tests)."
  @spec state(server()) :: term()
  @impl GeCrdt.AntiEntropy
  def state(server) do
    GenServer.call(server, :state)
  end

  @doc "Gossip one round to every neighbour immediately."
  @spec sync(server()) :: :ok
  @impl GeCrdt.AntiEntropy
  def sync(server) do
    GenServer.call(server, :sync_now)
  end

  @impl true
  def init({mod, id, opts}) do
    interval = Keyword.get(opts, :sync_interval, 100)
    initial = GeCrdt.Type.new(mod, id)

    discovery = Discovery.config_from_opts(opts, mod)

    if discovery do
      Discovery.ensure_scope(discovery.scope)
      Discovery.join(discovery)
    end

    st = %__MODULE__{
      crdt_module: mod,
      replica_id: id,
      crdt_state: initial,
      sync_interval: interval,
      sync_on_mutate: Keyword.get(opts, :sync_on_mutate, true),
      sync_strategy: Keyword.get(opts, :sync, Sync.DeltaInterval),
      neighbours: Keyword.get(opts, :neighbours, []),
      discovery: discovery,
      epoch: System.unique_integer([:positive, :monotonic])
    }

    if interval != :manual, do: schedule(interval)
    {:ok, st}
  end

  @impl true
  def handle_call({:set_neighbours, peers}, _from, st) do
    st = %{st | neighbours: peers}
    {:reply, :ok, %{st | acks: Discovery.prune_acks(st.acks, peers)}}
  end

  def handle_call({:mutate, op, args}, _from, st) do
    delta = Type.apply_mutation(st.crdt_module, st.crdt_state, op, args)

    st = %{
      st
      | crdt_state: st.crdt_module.join(st.crdt_state, delta),
        buffer: Map.put(st.buffer, st.seq, delta),
        seq: st.seq + 1
    }

    st = if st.sync_on_mutate, do: do_sync(st), else: st

    {:reply, :ok, st}
  end

  def handle_call(:read, _from, st) do
    {:reply, Type.query(st.crdt_module, st.crdt_state), st}
  end

  def handle_call(:state, _from, st) do
    {:reply, st.crdt_state, st}
  end

  def handle_call(:sync_now, _from, st) do
    {:reply, :ok, do_sync(st)}
  end

  @impl true
  def handle_info(:tick, st) do
    schedule(st.sync_interval)
    {:noreply, do_sync(st)}
  end

  def handle_info({:ge_crdt_delta, from, payload, n, epoch}, st) do
    send(from, {:ge_crdt_ack, self(), n, epoch})

    if from == self() or subsumed?(st, payload) do
      {:noreply, st}
    else
      st = %{
        st
        | crdt_state: st.crdt_module.join(st.crdt_state, payload),
          buffer: Map.put(st.buffer, st.seq, payload),
          seq: st.seq + 1
      }

      {:noreply, st}
    end
  end

  def handle_info({:ge_crdt_ack, from, n, epoch}, st) do
    if epoch == st.epoch do
      {:noreply, %{st | acks: Map.put(st.acks, from, max(Map.get(st.acks, from, 0), n))}}
    else
      {:noreply, st}
    end
  end

  defp schedule(interval) do
    Process.send_after(self(), :tick, interval)
  end

  # One gossip round: refresh membership, drop acks of departed
  # members, garbage-collect fully-acknowledged deltas, then let the
  # sync strategy decide each neighbour's payload.
  defp do_sync(st) do
    peers = Discovery.peers(st.neighbours, st.discovery)
    st = %{st | acks: Discovery.prune_acks(st.acks, peers)}
    st = gc(st)

    Enum.each(peers, fn peer -> maybe_send(st, peer) end)

    st
  end

  defp maybe_send(st, peer) do
    ctx = %{
      module: st.crdt_module,
      state: st.crdt_state,
      seq: st.seq,
      buffer: st.buffer,
      ack: Map.get(st.acks, peer, 0)
    }

    case st.sync_strategy.outgoing(ctx, peer) do
      :skip ->
        :ok

      {kind, payload, n} when kind in [:delta, :full] ->
        st.sync_strategy.deliver(peer, {:ge_crdt_delta, self(), payload, n, st.epoch})
    end
  end

  # Causal delta-merging precondition ingredients: a payload needs
  # joining only when it is not already subsumed (d ⊄ X).
  defp subsumed?(st, payload) do
    st.crdt_module.join(st.crdt_state, payload) == st.crdt_state
  end

  # Drop deltas acknowledged by every known neighbour (paper §6.1:
  # l = min ack, keep n >= l). With no acks yet, keep everything.
  defp gc(st) do
    case Map.values(st.acks) do
      [] ->
        st

      vals ->
        l = Enum.min(vals)
        %{st | buffer: Map.filter(st.buffer, fn {n, _} -> n >= l end)}
    end
  end
end
