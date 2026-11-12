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

  test "delta groups from both replicas match the full join" do
    o1 = RWSet.new("x")
    o2 = RWSet.new("y")
    do1 = RWSet.new()
    do2 = RWSet.new()

    {o1, d} = RWSet.add(o1, "a")
    do1 = RWSet.join(do1, d)
    {o1, d} = RWSet.add(o1, "b")
    do1 = RWSet.join(do1, d)

    {o2, d} = RWSet.add(o2, "b")
    do2 = RWSet.join(do2, d)
    {o2, d} = RWSet.add(o2, "c")
    do2 = RWSet.join(do2, d)
    {o2, d} = RWSet.remove(o2, "b")
    do2 = RWSet.join(do2, d)

    o3 = RWSet.join(o1, o2)
    o4 = RWSet.join(RWSet.join(o1, do1), RWSet.join(o2, do1))

    assert RWSet.read(o3) == MapSet.new(["a", "c"])
    assert RWSet.read(o4) == RWSet.read(o3)
    assert RWSet.read(do2) == MapSet.new(["c"])
    assert RWSet.member?(o3, "a")
    refute RWSet.member?(o3, "b")
    assert RWSet.member?(o3, "c")
  end
end
