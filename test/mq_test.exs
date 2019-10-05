defmodule MQTest do
  use ExUnit.Case
  doctest MQ

  test "greets the world" do
    assert MQ.hello() == :world
  end
end
