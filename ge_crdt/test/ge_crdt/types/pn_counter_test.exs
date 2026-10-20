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
end
