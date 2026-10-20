defmodule GeCrdt.Types.AWLWWSetTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.AWLWWSet

  test "newer timestamp wins" do
    s = %AWLWWSet{elements: %{"b" => {1, false}}}
    t = %AWLWWSet{elements: %{"b" => {2, true}}}
    assert s |> AWLWWSet.join(t) |> AWLWWSet.member?("b")
  end

  test "equal timestamps resolve add-wins" do
    s = %AWLWWSet{elements: %{"b" => {1, true}}}
    t = %AWLWWSet{elements: %{"b" => {1, false}}}
    assert s |> AWLWWSet.join(t) |> AWLWWSet.member?("b")
  end

  test "later remove hides the element across replicas" do
    s = %AWLWWSet{elements: %{"a" => {1, true}, "b" => {1, true}, "e" => {100, true}}}
    t = %AWLWWSet{elements: %{"b" => {2, false}}}

    j = AWLWWSet.join(s, t)
    assert AWLWWSet.member?(j, "a")
    refute AWLWWSet.member?(j, "b")
    assert AWLWWSet.member?(j, "e")
  end

  test "read returns only live elements" do
    s = %AWLWWSet{elements: %{"a" => {2, false}, "b" => {1, true}}}
    assert AWLWWSet.read(s) == MapSet.new(["b"])
    refute AWLWWSet.member?(s, "a")
  end

  test "mutators inflate the state and return a matching delta" do
    s = AWLWWSet.new()
    {s, d} = AWLWWSet.add(s, "a")
    assert AWLWWSet.join(s, d) == s
    assert AWLWWSet.member?(s, "a")

    # guarantee a strictly greater timestamp for the remove
    Process.sleep(1)
    {s2, d2} = AWLWWSet.remove(s, "a")
    assert AWLWWSet.join(s, d2) == s2
    refute AWLWWSet.member?(s2, "a")
  end
end
