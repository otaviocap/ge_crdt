defmodule GeCrdt.Types.RWSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.RWSet

  test "concurrent remove wins over add (README example)" do
    sx = RWSet.new("x")
    {sx, _} = RWSet.add(sx, "apple")
    {sx, _} = RWSet.remove(sx, "apple")

    sy = RWSet.new("y")
    {sy, _} = RWSet.add(sy, "juice")
    {sy, _} = RWSet.add(sy, "apple")

    assert RWSet.join(sx, sy) |> RWSet.read() == MapSet.new(["juice"])
  end

  test "plain adds are readable" do
    s = RWSet.new("a")
    {s, _} = RWSet.add(s, "a")
    {s, _} = RWSet.add(s, "b")
    assert RWSet.read(s) == MapSet.new(["a", "b"])
  end

  test "observed remove-then-add resurrects the element" do
    s = RWSet.new("a")
    {s, _} = RWSet.add(s, "x")
    {s, _} = RWSet.remove(s, "x")
    refute RWSet.member?(s, "x")
    {s, _} = RWSet.add(s, "x")
    assert RWSet.member?(s, "x")
  end

  test "clear empties the set" do
    s = RWSet.new("a")
    {s, _} = RWSet.add(s, "x")
    {s, _} = RWSet.clear(s)
    assert RWSet.read(s) == MapSet.new()
  end
end
