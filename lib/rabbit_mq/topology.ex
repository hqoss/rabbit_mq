defmodule Topology do
  use RabbitMQ.Topology,
    exchanges: [
      {"customer", :topic,
       [
         {"customer.created", "customer/customer.created", durable: true},
         {"customer.updated", "customer/customer.updated", durable: true},
         {"#", "customer/#"}
       ], durable: true}
    ]
end
