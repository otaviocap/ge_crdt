defmodule GeCrdt.Types.GSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.GSet
  alias GeCrdt.Utils.Join

  test "add makes elements readable" do
    s = GSet.new()
    {s, _} = GSet.add(s, "red")
    assert GSet.read(s) == MapSet.new(["red"])
    assert GSet.member?(s, "red")
    refute GSet.member?(s, "blue")
  end

  test "join is set union" do
    a = GSet.new()
    {a, _} = GSet.add(a, "red")
    b = GSet.new()
    {b, _} = GSet.add(b, "blue")
    assert GSet.join(a, b) |> GSet.read() == MapSet.new(["red", "blue"])
  end

  test "deltas ship only new elements (README example)" do
    sx = GSet.new()
    {sx, _} = GSet.add(sx, 1)
    {sx, _} = GSet.add(sx, 4)
    sy = sx
    {sy, d1} = GSet.add(sy, 2)
    {sy, d2} = GSet.add(sy, 3)

    dy = GSet.join(d1, d2)
    assert GSet.read(dy) == MapSet.new([2, 3])
    assert GSet.join(sx, dy) |> GSet.read() == MapSet.new([1, 2, 3, 4])
    assert GSet.read(sy) == MapSet.new([1, 2, 3, 4])
  end

  test "join is idempotent" do
    s = GSet.new()
    {s, d} = GSet.add(s, 1)
    assert GSet.join(s, d) == s
    assert GSet.join(s, s) == s
  end

  test "delta groups from both replicas match the full join" do
    o1 = GSet.new()
    o2 = GSet.new()
    do1 = GSet.new()
    do2 = GSet.new()

    {o1, d} = GSet.add(o1, 1)
    do1 = GSet.join(do1, d)
    {o1, d} = GSet.add(o1, 2)
    do1 = GSet.join(do1, d)

    {o2, d} = GSet.add(o2, 2)
    do2 = GSet.join(do2, d)
    {o2, d} = GSet.add(o2, 3)
    do2 = GSet.join(do2, d)

    o3 = GSet.join(o1, o2)
    o4 = Join.join(Join.join(o1, do2), Join.join(o2, do1))

    assert GSet.read(o3) == MapSet.new([1, 2, 3])
    assert GSet.read(o4) == GSet.read(o3)
  end
end
