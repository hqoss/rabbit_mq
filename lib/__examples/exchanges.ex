defmodule Examples.Config.Exchanges do
  def gen do
    [
      {"log",
       type: :topic,
       durable: true,
       routing_keys: [
         {"*.debug",
          queue: "log_queue/*.debug/sample-service", durable: true, dlq: "log_dead_letter_queue"},
         {"*.info",
          queue: "log_queue/*.info/sample-service", durable: true, dlq: "log_dead_letter_queue"},
         {"*.warn",
          queue: "log_queue/*.warn/sample-service", durable: true, dlq: "log_dead_letter_queue"},
         {"*.error",
          queue: "log_queue/*.error/sample-service", durable: true, dlq: "log_dead_letter_queue"},
         {"#", durable: false, exclusive: true, dlq: "log_dead_letter_queue"}
       ]}
    ]
  end
end
