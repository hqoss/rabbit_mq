defmodule Benchmark do
  @moduledoc false

  def measure(function) do
    function
    |> :timer.tc()
    |> elem(0)
    |> Integer.to_string()
    |> Kernel.<>("μs")

    # |> Kernel./(1_000_000)
  end
end
