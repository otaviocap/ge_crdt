defmodule GeCrdt.Types.AWORSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.AWORSet
  alias GeCrdt.Utils.DotContext

  test "added elements are readable" do
    s = AWORSet.new("a")
    {s, _} = AWORSet.add(s, "apple")
    assert AWORSet.read(s) == MapSet.new(["apple"])
    assert AWORSet.member?(s, "apple")
    refute AWORSet.member?(s, "juice")
  end

  test "remove drops observed elements" do
    s = AWORSet.new("a")
    {s, _} = AWORSet.add(s, "apple")
    {s, _} = AWORSet.remove(s, "apple")
    assert AWORSet.read(s) == MapSet.new()
  end

  test "concurrent add wins over remove (README example)" do
    sx = AWORSet.new("x")
    {sx, _} = AWORSet.add(sx, "apple")
    {sx, _} = AWORSet.remove(sx, "apple")

    sy = AWORSet.new("y")
    {sy, _} = AWORSet.add(sy, "juice")
    {sy, _} = AWORSet.add(sy, "apple")

    assert AWORSet.join(sx, sy) |> AWORSet.read() == MapSet.new(["apple", "juice"])
  end

  test "remove only affects observed adds" do
    x = AWORSet.new("a")
    {x, _} = AWORSet.add(x, 3.14)
    {x, _} = AWORSet.add(x, 2.718)
    {x, _} = AWORSet.remove(x, 3.14)

    y = AWORSet.new("b")
    {y, _} = AWORSet.add(y, 3.14)

    # x never saw y's dot for 3.14, so it survives the join
    assert AWORSet.join(x, y) |> AWORSet.read() == MapSet.new([3.14, 2.718])
  end

  test "joining deltas equals joining full states" do
    o1 = AWORSet.new("x")
    {o1, d1} = AWORSet.add(o1, "a")
    {o1, _d2} = AWORSet.add(o1, "b")

    o2 = AWORSet.new("y")
    {o2, _} = AWORSet.add(o2, "b")
    {o2, _} = AWORSet.add(o2, "c")
    {o2, _} = AWORSet.remove(o2, "b")

    full = AWORSet.join(o1, o2)
    via_deltas = o2 |> AWORSet.join(d1) |> AWORSet.join(o1)
    assert AWORSet.read(full) == AWORSet.read(via_deltas)
    assert AWORSet.member?(full, "b")
  end

  test "causal context stays contiguous (version-vector compressible, §7.2)" do
    s = AWORSet.new("a")
    {s, _} = AWORSet.add(s, 1)
    {s, _} = AWORSet.add(s, 2)
    {s, _} = AWORSet.remove(s, 1)
    ctx = AWORSet.context(s)
    assert ctx.dot_cloud == MapSet.new()
    assert DotContext.max_for(ctx, "a") == 2
  end

  test "reset clears observed elements" do
    s = AWORSet.new("a")
    {s, _} = AWORSet.add(s, 1)
    {s, _} = AWORSet.add(s, 2)
    {s, _} = AWORSet.reset(s)
    assert AWORSet.read(s) == MapSet.new()
  end
end
