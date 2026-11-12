defmodule GeCrdt.Utils.DotContext do
  @moduledoc """
  Causal context.
  Based on the DotContext available in the Delta Enabled CRDTs.

  A dot is `{replica_id, counter}`.

  The context has a counter part (`%{replica => max_counter}`)
  and a dot cloud (`MapSet` of non-compactable dots).
  """

  @type replica :: term()
  @type dot :: {replica(), pos_integer()}
  @type t :: %__MODULE__{
          replica_counter: %{optional(replica()) => non_neg_integer()},
          dot_cloud: MapSet.t(dot())
        }

  defstruct replica_counter: %{}, dot_cloud: MapSet.new()

  @doc "Empty context."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "True if dot is covered by the context."
  @spec dot_in?(t(), dot()) :: boolean()
  def dot_in?(%__MODULE__{replica_counter: replica_counter, dot_cloud: dot_cloud}, {id, n}) do
    case Map.fetch(replica_counter, id) do
      {:ok, max} when n <= max -> true
      _ -> MapSet.member?(dot_cloud, {id, n})
    end
  end

  @doc "Compact the dot cloud into causal context when contiguous."
  @spec compact(t()) :: t()
  def compact(%__MODULE__{} = ctx) do
    compact_loop(ctx)
  end

  defp compact_loop(ctx) do
    {new_ctx, flag} =
      Enum.reduce(
        ctx.dot_cloud,
        {%{ctx | dot_cloud: MapSet.new()}, false},
        fn {id, n} = dot,
           {%__MODULE__{} =
              acc, flag} ->
          case Map.fetch(acc.replica_counter, id) do
            :error ->
              if n == 1 do
                {%{acc | replica_counter: Map.put(acc.replica_counter, id, 1)}, true}
              else
                {%{acc | dot_cloud: MapSet.put(acc.dot_cloud, dot)}, flag}
              end

            {:ok, max} ->
              cond do
                n == max + 1 ->
                  {%{acc | replica_counter: Map.put(acc.replica_counter, id, max + 1)}, true}

                n <= max ->
                  {acc, flag}

                true ->
                  {%{acc | dot_cloud: MapSet.put(acc.dot_cloud, dot)}, flag}
              end
          end
        end
      )

    if flag, do: compact_loop(new_ctx), else: new_ctx
  end

  @doc """
  Generate a fresh dot for replica `id`, bumping the compact counter.
  Returns `{dot, new_context}`.
  """
  @spec make_dot(t(), replica()) :: {dot(), t()}
  def make_dot(%__MODULE__{replica_counter: replica_counter} = ctx, id) do
    n = Map.get(replica_counter, id, 0) + 1
    dot = {id, n}
    {dot, %{ctx | replica_counter: Map.put(replica_counter, id, n)}}
  end

  @doc "Insert a dot."
  @spec insert_dot(t(), dot(), boolean()) :: t()
  def insert_dot(%__MODULE__{} = ctx, dot, compact_now \\ true) do
    ctx = %{ctx | dot_cloud: MapSet.put(ctx.dot_cloud, dot)}
    if compact_now, do: compact(ctx), else: ctx
  end

  @doc "Join two contexts"
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    replica_counter =
      Map.merge(a.replica_counter, b.replica_counter, fn _k, x, y -> max(x, y) end)

    dot_cloud =
      Enum.reduce(b.dot_cloud, a.dot_cloud, fn d, acc -> MapSet.put(acc, d) end)
      |> then(fn dot_cloud ->
        %__MODULE__{replica_counter: replica_counter, dot_cloud: dot_cloud}
      end)
      |> compact()

    dot_cloud
  end

  @doc "Join a list of contexts."
  @spec join_all([t()]) :: t()
  def join_all(ctxs), do: Enum.reduce(ctxs, new(), &join(&2, &1))

  @doc "Max counter seen for replica `id`."
  @spec max_for(t(), replica()) :: non_neg_integer()
  def max_for(%__MODULE__{replica_counter: replica_counter}, id),
    do: Map.get(replica_counter, id, 0)
end
