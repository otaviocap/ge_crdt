defmodule GeCrdt.Types.EWFlagTest do
  use ExUnit.Case, async: true

  alias GeCrdt.Types.EWFlag

  test "starts disabled" do
    refute EWFlag.new("x") |> EWFlag.read()
  end

  test "enable then disable clears a lone flag" do
    s = EWFlag.new("x")
    {s, _} = EWFlag.enable(s)
    assert EWFlag.read(s)
    {s, _} = EWFlag.disable(s)
    refute EWFlag.read(s)
  end

  test "concurrent enable wins over disable" do
    a = EWFlag.new("x")
    {a, _} = EWFlag.enable(a)
    b = EWFlag.new("y")
    {b, _} = EWFlag.enable(b)
    {a, _} = EWFlag.disable(a)
    # b's enable dot was never observed by the disable, so it survives
    assert a |> EWFlag.join(b) |> EWFlag.read()
  end

  test "enable delta joins cleanly and idempotently" do
    a = EWFlag.new("x")
    {a, d} = EWFlag.enable(a)
    b = EWFlag.new("y")
    assert b |> EWFlag.join(d) |> EWFlag.read()
    assert EWFlag.join(a, d) == a
  end

  test "re-enabling is fine and a later disable propagates" do
    o1 = EWFlag.new("x")
    o2 = EWFlag.new("y")

    {o1, _} = EWFlag.enable(o1)
    {o2, _} = EWFlag.enable(o2)
    {o2, _} = EWFlag.enable(o2)

    o3 = EWFlag.join(o1, o2)
    assert EWFlag.read(o3)

    {o3, _} = EWFlag.disable(o3)
    o2 = EWFlag.join(o2, o3)
    refute EWFlag.read(o2)
  end
end
