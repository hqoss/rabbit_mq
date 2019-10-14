defmodule Core.ExponentialBackoff do
  @max_retries 6

  def with_backoff(func) do
    with_backoff(func, 0, 1, 0)
  end

  defp calc_timeout_ms(previous, current) do
    next = previous + current
    timeout_ms = next * 100
    {timeout_ms, current, next}
  end

  defp with_backoff(_func, _prev, _current, retry_count) when retry_count >= @max_retries do
    {:error, :max_retries_reached}
  end

  defp with_backoff(func, prev, current, retry_count) do
    case func.() do
      {:ok, _} = reply ->
        reply

      {:error, :max_retries_reached} = reply ->
        reply

      {:error, _} ->
        {timeout_ms, current, next} = calc_timeout_ms(prev, current)
        :timer.sleep(timeout_ms)
        with_backoff(func, current, next, retry_count + 1)
    end
  end
end
