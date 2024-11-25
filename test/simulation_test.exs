defmodule SimulationTest do
  use ExUnit.Case
  doctest Simulation

  test "greets the world" do
    assert Simulation.hello() == :world
  end
end
