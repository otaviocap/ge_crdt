defmodule GeCrdt.Discovery do
  @moduledoc """
  Shared `:pg`-based neighbour discovery for anti-entropy replicas.

  A discovery config is either `nil`/`false` (disabled), `true` (default
  scope with one group per CRDT module, so different types never exchange
  state), a named group, or `[scope: scope, group: group]`. Membership is
  read live from `:pg` on every gossip round, so cluster members that join
  the group are picked up automatically and dead members vanish on their
  own (`:pg` monitors its members).
  """

  @type config :: nil | %{required(:scope) => atom(), required(:group) => term()}

  @spec config(nil | false | true | keyword() | term(), module()) :: config()
  def config(nil, _mod), do: nil
  def config(false, _mod), do: nil
  def config(true, mod), do: %{scope: :pg, group: mod}

  def config(opts, mod) when is_list(opts) do
    %{scope: Keyword.get(opts, :scope, :pg), group: Keyword.get(opts, :group, mod)}
  end

  # Any other term is treated as a named group in the default scope.
  def config(group, _mod), do: %{scope: :pg, group: group}

  @doc """
  Resolve the discovery config from anti-entropy options.

  Accepts everything `config/2` does, plus a top-level `:group` option
  that enables discovery and takes precedence over the group inside
  `:discovery`. The scope is still taken from `:discovery` when given.
  """
  @spec config_from_opts(keyword(), module()) :: config()
  def config_from_opts(opts, mod) do
    case Keyword.fetch(opts, :group) do
      {:ok, group} ->
        scope =
          case Keyword.get(opts, :discovery) do
            discovery when is_list(discovery) -> Keyword.get(discovery, :scope, :pg)
            _ -> :pg
          end

        %{scope: scope, group: group}

      :error ->
        config(Keyword.get(opts, :discovery), mod)
    end
  end

  @doc """
  Start the `:pg` scope unless already running.

  Never links to the scope server: replicas must not take discovery
  down with them if they crash.
  """
  @spec ensure_scope(atom()) :: :ok
  def ensure_scope(:pg) do
    case :pg.start_link() do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _}} ->
        :ok
    end
  end

  def ensure_scope(scope) do
    case :pg.start_link(scope) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _}} ->
        :ok
    end
  end

  @doc "Join the discovery group as the current process."
  @spec join(config()) :: :ok | nil
  def join(nil), do: nil
  def join(%{scope: scope, group: group}), do: :pg.join(scope, group, self())

  @doc """
  Live group members (excluding the caller).

  Self-healing: if the scope server is down, it is restarted and the
  lookup retried once instead of silently reporting nobody home.
  """
  @spec members(config()) :: [pid()]
  def members(nil), do: []

  def members(%{scope: scope, group: group} = config) do
    :pg.get_members(scope, group) |> Enum.reject(&(&1 == self()))
  rescue
    ArgumentError ->
      ensure_scope(scope)
      members_once(config)
  end

  defp members_once(%{scope: scope, group: group}) do
    :pg.get_members(scope, group) |> Enum.reject(&(&1 == self()))
  rescue
    ArgumentError -> []
  end

  @doc "Manual neighbours plus live discovery members, deduplicated."
  @spec peers([pid()], config()) :: [pid()]
  def peers(manual, discovery) do
    (manual ++ members(discovery)) |> Enum.uniq() |> Enum.reject(&(&1 == self()))
  end

  @doc "Keep only acks belonging to current peers."
  @spec prune_acks(%{optional(pid()) => non_neg_integer()}, [pid()]) :: %{
          optional(pid()) => non_neg_integer()
        }
  def prune_acks(acks, peers) do
    Map.filter(acks, fn {p, _} -> p in peers end)
  end
end
