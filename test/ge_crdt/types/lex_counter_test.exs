defmodule GeCrdt.Types.LexCounterTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.LexCounter

  test "behaves like a PN-counter for the reference example" do
    x = LexCounter.new("a")
    {x, _} = LexCounter.increment(x, 4)
    {x, _} = LexCounter.decrement(x)

    y = LexCounter.new("b")
    {y, _} = LexCounter.decrement(y)

    assert LexCounter.join(x, y) |> LexCounter.value() == 2
  end

  test "decrement bumps the per-actor sequence number" do
    x = LexCounter.new("a")
    {x, dx} = LexCounter.increment(x, 3)
    assert dx.entries["a"] == {0, 3}
    {_, dd} = LexCounter.decrement(x, 1)
    assert dd.entries["a"] == {1, 2}
  end

  test "join keeps the lexicographic maximum per actor" do
    x = LexCounter.new("a")
    {x, _} = LexCounter.increment(x, 5)
    y = LexCounter.new("a")
    {y, _} = LexCounter.increment(y, 2)
    {y, _} = LexCounter.decrement(y, 1)
    # {1, 1} wins over {0, 5} on the sequence number
    assert LexCounter.join(x, y).entries["a"] == {1, 1}
  end
end
