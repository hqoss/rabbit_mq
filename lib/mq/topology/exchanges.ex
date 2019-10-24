defmodule MQ.Topology.Exchanges do
  @moduledoc """
  Defines the behaviour that the exchange config needs to implement.
  """

  @type exchange() :: {String.t(), keyword()}
  @callback gen() :: list(exchange())
end
