defmodule GeCrdt.Types.PNCounterTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.PNCounter

  test "increments minus decrements is the value" do
    x = PNCounter.new("a")
    {x, _} = PNCounter.increment(x, 4)
    {x, _} = PNCounter.decrement(x)
    assert PNCounter.value(x) == 3
  end

  test "concurrent increments and decrements merge" do
    x = PNCounter.new("a")
    {x, _} = PNCounter.increment(x, 4)
    {x, _} = PNCounter.decrement(x)

    y = PNCounter.new("b")
    {y, _} = PNCounter.decrement(y)

    assert PNCounter.join(x, y) |> PNCounter.value() == 2
  end

  test "join is commutative and idempotent" do
    x = PNCounter.new("a")
    {x, dx} = PNCounter.increment(x, 4)
    y = PNCounter.new("b")
    {y, _} = PNCounter.decrement(y)

    assert PNCounter.value(PNCounter.join(x, y)) == PNCounter.value(PNCounter.join(y, x))
    assert PNCounter.join(x, dx) == x
  end

  test "delta groups from both replicas match the full join" do
    o1 = PNCounter.new(2)
    o2 = PNCounter.new(5)
    do1 = PNCounter.new()
    do2 = PNCounter.new()

    {o1, d} = PNCounter.increment(o1, 3.5)
    do1 = PNCounter.join(do1, d)
    {o1, d} = PNCounter.decrement(o1, 2)
    do1 = PNCounter.join(do1, d)

    {o2, d} = PNCounter.increment(o2)
    do2 = PNCounter.join(do2, d)
    {o2, d} = PNCounter.increment(o2, 5)
    do2 = PNCounter.join(do2, d)

    o3 = PNCounter.join(o1, o2)
    o4 = PNCounter.join(PNCounter.join(o1, do2), PNCounter.join(o2, do1))

    assert PNCounter.value(o3) == 7.5
    assert PNCounter.value(o4) == PNCounter.value(o3)
  end
end
