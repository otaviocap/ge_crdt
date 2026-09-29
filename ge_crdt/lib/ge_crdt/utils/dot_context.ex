defmodule GeCrdt.Utils.DotContext do
  @moduledoc """
  Autonomous causal context.
  Based on the DotContext available in the Delta Enabled CRDTs.

  A dot is `{replica_id, counter}`.

  The context has a compact part (`%{replica => max_counter}` for contiguous sequences)
  and a dot cloud (`MapSet` of non-compactable dots).
  """

  @type replica :: term()
  @type dot :: {replica(), pos_integer()}
  @type t :: %__MODULE__{cc: %{optional(replica()) => non_neg_integer()}, dc: MapSet.t(dot())}

  defstruct cc: %{}, dc: MapSet.new()

  @doc "Empty context."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "True if dot is covered by the context."
  @spec dot_in?(t(), dot()) :: boolean()
  def dot_in?(%__MODULE__{cc: cc, dc: dc}, {id, n}) do
    case Map.fetch(cc, id) do
      {:ok, max} when n <= max -> true
      _ -> MapSet.member?(dc, {id, n})
    end
  end

  @doc "Compact the dot cloud into causal context when contiguous."
  @spec compact(t()) :: t()
  def compact(%__MODULE__{} = ctx) do
    compact_loop(ctx)
  end

  defp compact_loop(ctx) do
    {new_ctx, flag} =
      Enum.reduce(ctx.dc, {%{ctx | dc: MapSet.new()}, false}, fn {id, n} = dot,
                                                                 {%__MODULE__{} = acc, flag} ->
        case Map.fetch(acc.cc, id) do
          :error ->
            if n == 1 do
              {%{acc | cc: Map.put(acc.cc, id, 1)}, true}
            else
              {%{acc | dc: MapSet.put(acc.dc, dot)}, flag}
            end

          {:ok, max} ->
            cond do
              n == max + 1 ->
                {%{acc | cc: Map.put(acc.cc, id, max + 1)}, true}

              n <= max ->
                {acc, flag}

              true ->
                {%{acc | dc: MapSet.put(acc.dc, dot)}, flag}
            end
        end
      end)

    if flag, do: compact_loop(new_ctx), else: new_ctx
  end

  @doc """
  Generate a fresh dot for replica `id`, bumping the compact counter.
  Returns `{dot, new_context}`.
  """
  @spec make_dot(t(), replica()) :: {dot(), t()}
  def make_dot(%__MODULE__{cc: cc} = ctx, id) do
    n = Map.get(cc, id, 0) + 1
    dot = {id, n}
    {dot, %{ctx | cc: Map.put(cc, id, n)}}
  end

  @doc "Insert a dot."
  @spec insert_dot(t(), dot(), boolean()) :: t()
  def insert_dot(%__MODULE__{} = ctx, dot, compact_now \\ true) do
    ctx = %{ctx | dc: MapSet.put(ctx.dc, dot)}
    if compact_now, do: compact(ctx), else: ctx
  end

  @doc "Join two contexts"
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    cc =
      Map.merge(a.cc, b.cc, fn _k, x, y -> max(x, y) end)

    dc =
      Enum.reduce(b.dc, a.dc, fn d, acc -> MapSet.put(acc, d) end)
      |> then(fn dc -> %__MODULE__{cc: cc, dc: dc} end)
      |> compact()

    dc
  end

  @doc "Join a list of contexts."
  @spec join_all([t()]) :: t()
  def join_all(ctxs), do: Enum.reduce(ctxs, new(), &join(&2, &1))

  @doc "Max counter seen for replica `id`."
  @spec max_for(t(), replica()) :: non_neg_integer()
  def max_for(%__MODULE__{cc: cc}, id), do: Map.get(cc, id, 0)
end
