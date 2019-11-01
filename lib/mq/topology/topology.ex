defmodule MQ.Topology do
  @moduledoc """
  Defines the behaviour that the topology config needs to implement.
  """

  @type exchange() :: {String.t(), keyword()}
  @callback gen() :: list(exchange())
end
