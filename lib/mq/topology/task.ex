defmodule Mix.Tasks.Rabbit.Init do
  alias MQ.Topology.Setup

  use Mix.Task

  @shortdoc "Sets up all exchanges and queues for the dev and test environments"
  @spec run(any()) :: {:ok, any()}
  def run(_) do
    Setup.run()
  end
end
