use Mix.Config

config :logger,
  backends: [{Logger.Backends.File, :dev_backend}],
  level: :info,
  format: "$time $metadata[$level] $message\n"

config :logger, :dev_backend,
  level: :error,
  path: "test/$date/$a_error.log",
  format: "DEV $message $a\n",
  metadata: [:a],
  opts: [{:delayed_write, 1024, :timer.seconds(2)}]
