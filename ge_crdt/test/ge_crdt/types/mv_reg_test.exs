defmodule GeCrdt.Types.MVRegTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.MVReg

  test "sequential writes overwrite" do
    x = MVReg.new("x")
    {x, _} = MVReg.write(x, "hello")
    {x, _} = MVReg.write(x, "world")
    assert MVReg.read(x) == MapSet.new(["world"])
  end

  test "concurrent writes become siblings" do
    x = MVReg.new("x")
    {x, _} = MVReg.write(x, "hello")
    {x, _} = MVReg.write(x, "world")

    y = MVReg.new("y")
    {y, _} = MVReg.write(y, "world")
    {y, _} = MVReg.write(y, "hello")

    assert MVReg.join(x, y) |> MVReg.read() == MapSet.new(["hello", "world"])
  end

  test "a write after observing clears all siblings" do
    x = MVReg.new("x")
    {x, _} = MVReg.write(x, "hello")
    y = MVReg.new("y")
    {y, _} = MVReg.write(y, "world")
    j = MVReg.join(x, y)
    {j, _} = MVReg.write(j, "mars")
    assert MVReg.read(j) == MapSet.new(["mars"])
    assert MVReg.join(x, j) |> MVReg.read() == MapSet.new(["mars"])
  end

  test "resolve keeps only maximal siblings" do
    a = MVReg.new("a")
    {a, _} = MVReg.write(a, 0)
    b = MVReg.new("b")
    {b, _} = MVReg.write(b, 3)
    {j, _} = a |> MVReg.join(b) |> MVReg.resolve()
    assert MVReg.read(j) == MapSet.new([3])
  end

  test "write delta carries one dot and joins cleanly" do
    x = MVReg.new("x")
    {x, d} = MVReg.write(x, "hello")
    assert map_size(d.kernel.dot_store) == 1
    y = MVReg.new("y")
    assert MVReg.join(y, d) |> MVReg.read() == MapSet.new(["hello"])
    assert MVReg.join(x, d) == x
  end
end
