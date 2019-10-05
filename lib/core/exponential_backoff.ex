defmodule Core.ExponentialBackoff do
  @max_retries 12

  def calc_timeout_ms(previous \\ 0, current \\ 1) do
    next = previous + current
    timeout_ms = next * 100
    {timeout_ms, current, next}
  end

  def with_backoff(_func, _prev, _current, retry_count) when retry_count >= @max_retries do
    {:error, :max_retries_reached}
  end

  def with_backoff(func, prev \\ 0, current \\ 1, retry_count \\ 0) do
    case func.() do
      {:ok, _} = result ->
        result

      {:error, _} ->
        {timeout_ms, current, next} = calc_timeout_ms(prev, current)
        :timer.sleep(timeout_ms)
        with_backoff(func, current, next, retry_count + 1)
    end
  end
end
