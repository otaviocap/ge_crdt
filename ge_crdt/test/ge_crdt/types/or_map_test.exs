defmodule GeCrdt.Types.ORMapTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.{AWSet, MVReg, ORMap}

  test "entries hold independent CRDTs that merge on join" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "paint", AWSet.new(), &AWSet.add(&1, "blue"))

    n = ORMap.new("y")
    {n, _} = ORMap.update(n, "paint", AWSet.new(), &AWSet.add(&1, "red"))
    {n, _} = ORMap.update(n, "number", AWSet.new(), &AWSet.add(&1, "42"))

    j = ORMap.join(m, n)
    assert j.entries["paint"] |> AWSet.read() == MapSet.new(["blue", "red"])
    assert j.entries["number"] |> AWSet.read() == MapSet.new(["42"])
  end

  test "nested remove propagates to replicas holding the key" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "paint", AWSet.new(), &AWSet.add(&1, "blue"))
    n = ORMap.new("y")
    {n, _} = ORMap.update(n, "paint", AWSet.new(), &AWSet.add(&1, "red"))
    j = ORMap.join(m, n)

    {j, _} = ORMap.update(j, "paint", AWSet.new(), &AWSet.remove(&1, "red"))
    assert ORMap.join(j, n).entries["paint"] |> AWSet.member?("red") == false
    assert ORMap.join(j, n).entries["paint"] |> AWSet.member?("blue")
  end

  test "delete is an observed reset: concurrent adds survive" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "c", AWSet.new(), &AWSet.add(&1, "red"))
    {m, _} = ORMap.delete(m, "c")

    n = ORMap.new("y")
    {n, _} = ORMap.update(n, "c", AWSet.new(), &AWSet.add(&1, "green"))

    assert ORMap.join(m, n).entries["c"] |> AWSet.read() == MapSet.new(["green"])
  end

  test "delete leaves an empty tombstone once observed everywhere" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "c", AWSet.new(), &AWSet.add(&1, "red"))
    n = ORMap.join(ORMap.new("y"), m)
    {n, _} = ORMap.delete(n, "c")
    joined = ORMap.join(m, n)
    assert joined.entries["c"] |> AWSet.read() == MapSet.new()
    refute ORMap.has_key?(joined, "c")
  end

  test "maps nest: outer join merges inner maps" do
    ma = ORMap.new("alice")

    {ma, _} =
      ORMap.update(ma, 23, ORMap.new(), fn inner ->
        ORMap.update(inner, "color", AWSet.new(), &AWSet.add(&1, "red at 23"))
      end)

    mb = ORMap.new("bob")

    {mb, _} =
      ORMap.update(mb, 44, ORMap.new(), fn inner ->
        ORMap.update(inner, "sound", AWSet.new(), &AWSet.add(&1, "soft at 44"))
      end)

    j = ORMap.join(ma, mb)
    assert map_size(j.entries) == 2
    assert j.entries[44].entries["sound"] |> AWSet.read() == MapSet.new(["soft at 44"])
  end

  test "register entries work inside the map" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "greeting", MVReg.new(), &MVReg.write(&1, "hello"))
    {m, _} = ORMap.update(m, "greeting", MVReg.new(), &MVReg.write(&1, "world"))

    assert m.entries["greeting"] |> MVReg.read() == MapSet.new(["world"])
    assert ORMap.read(m) == %{"greeting" => MapSet.new(["world"])}
  end

  test "clear erases every key" do
    m = ORMap.new("x")
    {m, _} = ORMap.update(m, "a", AWSet.new(), &AWSet.add(&1, 1))
    {m, _} = ORMap.update(m, "b", AWSet.new(), &AWSet.add(&1, 2))
    {m, _} = ORMap.clear(m)

    assert ORMap.read(m) == %{}
    assert ORMap.keys(m) == []
  end

  test "erase and clear are observed resets across replicas" do
    m = ORMap.new("x")
    n = ORMap.new("y")

    {m, _} = ORMap.update(m, "color", AWSet.new(), &AWSet.add(&1, "red"))
    {m, _} = ORMap.update(m, "taste", AWSet.new(), &AWSet.add(&1, "bitter"))
    {n, _} = ORMap.update(n, "sound", AWSet.new(), &AWSet.add(&1, "loud"))
    {n, _} = ORMap.update(n, "color", AWSet.new(), &AWSet.add(&1, "blue"))

    m = ORMap.join(m, n)
    assert ORMap.read(m)["color"] == MapSet.new(["blue", "red"])

    {n, _} = ORMap.delete(n, "sound")
    m = ORMap.join(m, n)

    assert ORMap.get(m, "sound", AWSet.new()) |> AWSet.read() == MapSet.new()

    {m, _} = ORMap.delete(m, "color")
    {m, _} = ORMap.clear(m)
    m = ORMap.join(m, n)

    assert ORMap.read(m) == %{}
    assert ORMap.keys(m) == []
  end
end
