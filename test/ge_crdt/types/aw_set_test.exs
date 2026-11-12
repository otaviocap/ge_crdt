defmodule GeCrdt.Types.AWSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.AWSet
  alias GeCrdt.Utils.DotContext

  test "added elements are readable" do
    s = AWSet.new("a")
    {s, _} = AWSet.add(s, "apple")
    assert AWSet.read(s) == MapSet.new(["apple"])
    assert AWSet.member?(s, "apple")
    refute AWSet.member?(s, "juice")
  end

  test "remove drops observed elements" do
    s = AWSet.new("a")
    {s, _} = AWSet.add(s, "apple")
    {s, _} = AWSet.remove(s, "apple")
    assert AWSet.read(s) == MapSet.new()
  end

  test "concurrent add wins over remove (README example)" do
    sx = AWSet.new("x")
    {sx, _} = AWSet.add(sx, "apple")
    {sx, _} = AWSet.remove(sx, "apple")

    sy = AWSet.new("y")
    {sy, _} = AWSet.add(sy, "juice")
    {sy, _} = AWSet.add(sy, "apple")

    assert AWSet.join(sx, sy) |> AWSet.read() == MapSet.new(["apple", "juice"])
  end

  test "remove only affects observed adds" do
    x = AWSet.new("a")
    {x, _} = AWSet.add(x, 3.14)
    {x, _} = AWSet.add(x, 2.718)
    {x, _} = AWSet.remove(x, 3.14)

    y = AWSet.new("b")
    {y, _} = AWSet.add(y, 3.14)

    # x never saw y's dot for 3.14, so it survives the join
    assert AWSet.join(x, y) |> AWSet.read() == MapSet.new([3.14, 2.718])
  end

  test "joining deltas equals joining full states" do
    o1 = AWSet.new("x")
    {o1, d1} = AWSet.add(o1, "a")
    {o1, _d2} = AWSet.add(o1, "b")

    o2 = AWSet.new("y")
    {o2, _} = AWSet.add(o2, "b")
    {o2, _} = AWSet.add(o2, "c")
    {o2, _} = AWSet.remove(o2, "b")

    full = AWSet.join(o1, o2)
    via_deltas = o2 |> AWSet.join(d1) |> AWSet.join(o1)
    assert AWSet.read(full) == AWSet.read(via_deltas)
    assert AWSet.member?(full, "b")
  end

  test "causal context stays contiguous (version-vector compressible, §7.2)" do
    s = AWSet.new("a")
    {s, _} = AWSet.add(s, 1)
    {s, _} = AWSet.add(s, 2)
    {s, _} = AWSet.remove(s, 1)
    ctx = AWSet.context(s)
    assert ctx.dot_cloud == MapSet.new()
    assert DotContext.max_for(ctx, "a") == 2
  end

  test "reset clears observed elements" do
    s = AWSet.new("a")
    {s, _} = AWSet.add(s, 1)
    {s, _} = AWSet.add(s, 2)
    {s, _} = AWSet.reset(s)
    assert AWSet.read(s) == MapSet.new()
  end
end
