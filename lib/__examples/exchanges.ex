defmodule Examples.Config.Exchanges do
  def gen do
    [
      {"audit_log",
       type: :topic,
       durable: true,
       routing_keys: [
         {"#",
          queue: "audit_log_queue/#/example", durable: true, dlq: "audit_log_dead_letter_queue"}
       ]},
      {"log",
       type: :topic,
       durable: true,
       routing_keys: [
         {"#", queue: "log_queue/#/example", durable: true, dlq: "log_dead_letter_queue"},
         {"*.error",
          queue: "log_queue/*.error/example", durable: true, dlq: "log_dead_letter_queue"},
         {"#", durable: false, exclusive: true, dlq: "log_dead_letter_queue"}
       ]}
    ]
  end
end
