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
end
