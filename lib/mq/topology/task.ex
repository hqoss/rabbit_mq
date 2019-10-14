defmodule Mix.Tasks.Rabbit.Init do
  alias Examples.Config.Exchanges
  alias MQ.Topology.{Config, Setup}

  use Mix.Task

  @shortdoc "Sets up all exchanges and queues for the dev and test environments"
  @spec run(any()) :: {:ok, any()}
  def run(_) do
    # Mix.Task.run("app.start")

    Exchanges.gen()
    |> Config.gen()
    |> Setup.run()
  end
end
