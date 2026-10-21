defmodule GeCrdt.AntiEntropy.Basic do
  @moduledoc """
  Basic anti-entropy (based on Algorithm 1 from Almeida et al.,
  "Efficient State-based CRDTs by Delta-Mutation).

  Each process holds one replica: the CRDT state `X` plus a volatile
  buffer `D` accumulating locally-generated (and, in transitive mode,
  received) deltas into one delta-group. Gossip rounds broadcast either
  the buffered delta-group or the full state; receivers simply join
  whatever arrives. No sequence numbers, no acknowledgments. Delivery
  is eventually consistent but not causally so (use
  `GeCrdt.AntiEntropy.Causal` when causal consistency matters).

  Modes (paper inputs):

  - `:transitive` (default `true`), received deltas also join the
    buffer, so replicas forward what they learn;
  - `:ship`
      - `:delta` (default) broadcasts the buffered delta-group,
      - `:full` always broadcasts the full state.
  """

  @behaviour GeCrdt.AntiEntropy

  use GenServer

  alias GeCrdt.{Discovery, Type}

  @type server :: GenServer.server()

  defstruct crdt_module: nil,
            replica_id: nil,
            crdt_state: nil,
            sync_interval: 100,
            sync_on_mutate: true,
            transitive: true,
            ship: :delta,
            neighbours: [],
            discovery: nil,
            buffer: nil,
            epoch: nil

  @doc """
  Start a replica of `crdt_module` identified by `replica_id`.

  Options: `:neighbours`, `:sync_interval` (`:manual` disables the
  timer), `:sync_on_mutate` (default `true`), `:discovery`,
  `:transitive` (default `true`), `:ship` (`:delta` or `:full`,
  default `:delta`), `:group`, `:name`.

  `:group` connects to a named `:pg` group instead of the default group
  named after the CRDT module. It can also be given as a bare term in
  `:discovery` (e.g. `discovery: :my_group`).
  """
  @spec start_link(module(), term(), keyword()) :: GenServer.on_start()
  @impl GeCrdt.AntiEntropy
  def start_link(crdt_module, replica_id, opts \\ []) do
    {gen_opts, opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, {crdt_module, replica_id, opts}, gen_opts)
  end

  @doc "Replace the manual neighbour set."
  @spec set_neighbours(server(), [pid()]) :: :ok
  @impl GeCrdt.AntiEntropy
  def set_neighbours(server, neighbours) do
    GenServer.call(server, {:set_neighbours, neighbours})
  end

  @doc "Apply `op` with `args` to the local state."
  @spec mutate(server(), atom(), [term()]) :: :ok
  @impl GeCrdt.AntiEntropy
  def mutate(server, op, args \\ []) do
    GenServer.call(server, {:mutate, op, args})
  end

  @doc "Run the type's query against the local state."
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
      transitive: Keyword.get(opts, :transitive, true),
      ship: Keyword.get(opts, :ship, :delta),
      neighbours: Keyword.get(opts, :neighbours, []),
      discovery: discovery,
      epoch: System.unique_integer([:positive, :monotonic])
    }

    if interval != :manual, do: schedule(interval)
    {:ok, st}
  end

  @impl true
  def handle_call({:set_neighbours, peers}, _from, st) do
    {:reply, :ok, %{st | neighbours: peers}}
  end

  def handle_call({:mutate, op, args}, _from, st) do
    delta = Type.apply_mutation(st.crdt_module, st.crdt_state, op, args)

    st = %{
      st
      | crdt_state: st.crdt_module.join(st.crdt_state, delta),
        buffer: join_buffer(st, delta)
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
    # Acknowledge so causal senders advance; Basic itself keeps no acks.
    send(from, {:ge_crdt_ack, self(), n, epoch})

    st = %{st | crdt_state: st.crdt_module.join(st.crdt_state, payload)}

    st =
      if st.transitive and from != self() do
        %{st | buffer: join_buffer(st, payload)}
      else
        st
      end

    {:noreply, st}
  end

  # Acks are not used here as on basic the full state is sent every time
  def handle_info({:ge_crdt_ack, _from, _n, _epoch}, st) do
    {:noreply, st}
  end

  defp schedule(interval) do
    Process.send_after(self(), :tick, interval)
  end

  defp join_buffer(%{buffer: nil}, delta), do: delta
  defp join_buffer(st, delta), do: st.crdt_module.join(st.buffer, delta)

  defp do_sync(st) do
    peers = Discovery.peers(st.neighbours, st.discovery)

    payload =
      case {st.ship, st.buffer} do
        {:full, _} -> st.crdt_state
        {:delta, nil} -> nil
        {:delta, buffer} -> buffer
      end

    if payload != nil do
      Enum.each(peers, fn peer ->
        send(peer, {:ge_crdt_delta, self(), payload, 0, st.epoch})
      end)
    end

    st
  end
end
