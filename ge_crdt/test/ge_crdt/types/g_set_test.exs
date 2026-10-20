defmodule GeCrdt.Types.GSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.GSet

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
end
