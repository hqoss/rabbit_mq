defmodule Core.ExponentialBackoff do
  def calc_timeout_ms(previous \\ 0, current \\ 1) do
    next = previous + current
    timeout_ms = next * 100
    {timeout_ms, current, next}
  end

  def with_backoff(func, prev \\ 0, current \\ 1) do
    case func.() do
      {:ok, _} = result ->
        result

      {:error, _} ->
        {timeout_ms, current, next} = calc_timeout_ms(prev, current)
        :timer.sleep(timeout_ms)
        with_backoff(func, current, next)
    end
  end
end
