defmodule GeCrdt.Types.GCounterTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.GCounter

  test "increment returns a single-entry delta" do
    x = GCounter.new("x")
    {x, d} = GCounter.increment(x)
    assert d.counts == %{"x" => 1}
    assert x.counts == %{"x" => 1}
  end

  test "value sums all replica entries" do
    x = GCounter.new("x")
    {x, _} = GCounter.increment(x)
    {x, _} = GCounter.increment(x, 4)
    y = GCounter.new("y")
    {y, _} = GCounter.increment(y, 2)
    assert GCounter.value(GCounter.join(x, y)) == 7
  end

  test "join is idempotent: rejoining a delta changes nothing" do
    x = GCounter.new("x")
    {x, d} = GCounter.increment(x, 3)
    assert GCounter.join(x, d) == x
  end

  test "delta-group collapses increments and matches the full state join" do
    x = GCounter.new("x")
    {x, d1} = GCounter.increment(x)
    {x, d2} = GCounter.increment(x, 4)
    y = GCounter.new("y")
    {y, _} = GCounter.increment(y, 2)

    group = GCounter.join(d1, d2)
    assert group.counts == %{"x" => 5}
    assert GCounter.join(y, group) == GCounter.join(y, x)
  end

  test "convergence: every delta joined everywhere equalizes replicas (Prop. 1)" do
    a = GCounter.new("a")
    {a, da} = GCounter.increment(a, 2)
    b = GCounter.new("b")
    {b, db} = GCounter.increment(b, 3)
    c = GCounter.new("c")
    {c, dc} = GCounter.increment(c, 5)

    converged =
      [a, b, c]
      |> Enum.map(&GCounter.join(&1, da))
      |> Enum.map(&GCounter.join(&1, db))
      |> Enum.map(&GCounter.join(&1, dc))

    assert Enum.map(converged, & &1.counts) |> Enum.uniq() == [%{"a" => 2, "b" => 3, "c" => 5}]
    assert Enum.map(converged, &GCounter.value/1) |> Enum.uniq() == [10]
  end
end
