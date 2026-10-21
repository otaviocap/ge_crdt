defmodule GeCrdt.Types.TwoPSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.{GSet, TwoPSet}

  test "add then remove hides the element" do
    s = TwoPSet.new()
    {s, _} = TwoPSet.add(s, "my")
    assert TwoPSet.member?(s, "my")
    {s, _} = TwoPSet.remove(s, "my")
    refute TwoPSet.member?(s, "my")
  end

  test "removed elements cannot be re-added" do
    s = TwoPSet.new()
    {s, _} = TwoPSet.add(s, 1)
    {s, _} = TwoPSet.remove(s, 1)
    {s, _} = TwoPSet.add(s, 1)
    refute TwoPSet.member?(s, 1)
  end

  test "join keeps tombstones across replicas" do
    a = TwoPSet.new()
    {a, _} = TwoPSet.add(a, 3.14)
    {a, _} = TwoPSet.remove(a, 3.14)

    b = TwoPSet.new()
    {b, _} = TwoPSet.add(b, 42)
    {b, _} = TwoPSet.add(b, 3.14)

    assert TwoPSet.join(a, b) |> TwoPSet.read() == MapSet.new([42])
  end

  test "content matches an equivalent GSet" do
    t = TwoPSet.new()
    {t, _} = TwoPSet.add(t, 42)

    g = GSet.new()
    {g, _} = GSet.add(g, 42)

    assert TwoPSet.read(t) == GSet.read(g)
  end

  test "delta groups from both replicas match the full join" do
    o1 = TwoPSet.new()
    o2 = TwoPSet.new()
    do1 = TwoPSet.new()
    do2 = TwoPSet.new()

    {o1, d} = TwoPSet.add(o1, 1)
    do1 = TwoPSet.join(do1, d)
    {o1, d} = TwoPSet.add(o1, 2)
    do1 = TwoPSet.join(do1, d)

    {o2, d} = TwoPSet.add(o2, 2)
    do2 = TwoPSet.join(do2, d)
    {o2, d} = TwoPSet.remove(o2, 2)
    do2 = TwoPSet.join(do2, d)

    o3 = TwoPSet.join(o1, o2)
    o4 = TwoPSet.join(TwoPSet.join(o1, do1), TwoPSet.join(o2, do1))

    assert TwoPSet.read(o3) == MapSet.new([1])
    assert TwoPSet.read(o4) == TwoPSet.read(o3)
    assert TwoPSet.member?(o3, 1)
    refute TwoPSet.member?(o3, 2)
    assert TwoPSet.read(do2) == MapSet.new()
  end

  test "removing the same element twice is idempotent" do
    s = TwoPSet.new()
    {s, _} = TwoPSet.add(s, "x")
    {s, _} = TwoPSet.remove(s, "x")
    {s, d} = TwoPSet.remove(s, "x")

    assert TwoPSet.read(s) == MapSet.new()
    assert TwoPSet.join(s, d) == s
  end
end
