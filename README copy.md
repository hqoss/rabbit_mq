# 🐇 rabbit_mq_ex

The missing RabbitMQ client for Elixir.

## 

## Core concepts and architecture

* Each Producer module is implicitly converted into a pool of supervised producer workers with round-robin dispatch
* Each Producer module implicitly creates and supervises its own connection
* Each Consumer module is is implicitly converted into a group of supervised consumer workers
* Each Consumer module implicitly creates and supervises its own connection
* There are sensible defaults
* There are imposed requirements
* There is a application-scoped limit of channels per connection

