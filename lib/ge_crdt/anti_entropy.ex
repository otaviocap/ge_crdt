defmodule GeCrdt.AntiEntropy do
  @moduledoc """
  Behaviour for anti-entropy replicas

  Each anti_entropy process has one replica of a `GeCrdt.Type` and gossips
  deltas until all replicas converge. Every implementation has:

  - `start_link/3` with `:neighbours`, `:sync_interval` (`:manual`
    disables the timer), `:sync_on_mutate` (gossip right after every
    local `mutate/3`, default `true`), `:discovery` (`:pg`-based
    auto-neighbours, optionally naming a group), `:group` (connect to a
    named `:pg` group instead of the module-named default) and `:name`;
  - `mutate/3` applies `apply(type, op, [state | args])` and pushes the
    delta out (subject to `sync_on_mutate`);
  - `read/1` runs the type's query, `state/1` returns the raw state,
    `sync/1` gossips one round immediately,
    `set_neighbours/2` replaces the manual neighbour list.

  Swap the default globally (e.g. in `config.exs`):

      config :ge_crdt, anti_entropy: GeCrdt.AntiEntropy.Basic

  or use an implementation module directly:

      alias GeCrdt.{AntiEntropy, Types.GCounter}
      {:ok, a} = AntiEntropy.start_link(GCounter, "a", sync_interval: :manual)
      {:ok, b} = AntiEntropy.start_link(GCounter, "b", sync_interval: :manual)
      AntiEntropy.set_neighbours(a, [b])
      AntiEntropy.set_neighbours(b, [a])
      AntiEntropy.mutate(a, :increment, [2])
      AntiEntropy.mutate(b, :increment, [3])
  """

  @doc "Start a replica of `crdt_module` identified by `replica_id`."
  @callback start_link(module(), term(), keyword()) :: GenServer.on_start()

  @doc "Replace the manual neighbour set."
  @callback set_neighbours(GenServer.server(), [pid()]) :: :ok

  @doc "Apply `op` with `args` to the local state."
  @callback mutate(GenServer.server(), atom(), [term()]) :: :ok

  @doc "Run the type's query against the local state."
  @callback read(GenServer.server()) :: term()

  @doc "Return the raw CRDT state."
  @callback state(GenServer.server()) :: term()

  @doc "Gossip one round to every neighbour immediately."
  @callback sync(GenServer.server()) :: :ok

  @doc """
  Start a replica with the configured implementation (see moduledoc).
  Same options as the implementations.
  """
  @spec start_link(module(), term(), keyword()) :: GenServer.on_start()
  def start_link(crdt_module, replica_id, opts \\ []) do
    impl().start_link(crdt_module, replica_id, opts)
  end

  @doc "Replace the manual neighbour set."
  @spec set_neighbours(GenServer.server(), [pid()]) :: :ok
  def set_neighbours(server, neighbours) do
    impl().set_neighbours(server, neighbours)
  end

  @doc """
  Apply `op` with `args` to the local state.

  Invokes `apply(crdt_module, op, [state | args])`; the delta is joined
  locally and gossiped subject to `sync_on_mutate`.
  """
  @spec mutate(GenServer.server(), atom(), [term()]) :: :ok
  def mutate(server, op, args \\ []) do
    impl().mutate(server, op, args)
  end

  @doc """
  Run the type's query against the local state (`read/1` when exported,
  otherwise `value/1`).
  """
  @spec read(GenServer.server()) :: term()
  def read(server) do
    impl().read(server)
  end

  @doc "Return the raw CRDT state (useful in tests)."
  @spec state(GenServer.server()) :: term()
  def state(server) do
    impl().state(server)
  end

  @doc "Gossip one round to every neighbour immediately."
  @spec sync(GenServer.server()) :: :ok
  def sync(server) do
    impl().sync(server)
  end

  defp impl do
    Application.get_env(:ge_crdt, :anti_entropy, GeCrdt.AntiEntropy.Causal)
  end
end
