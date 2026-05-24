# ReqLogger

[Req](https://github.com/wojtekmach/req) Logger plugin.

## Installation

```elixir
def deps do
  [
    {:req_logger, "~> 0.1.0", github: "adriankumpf/req_logger"}
  ]
end
```

## Usage

```elixir
Mix.install([
  {:req, "~> 0.5.0"},
  {:req_logger, "~> 0.1.0", github: "adriankumpf/req_logger"}
])

req =
  Req.new()
  |> ReqLogger.attach()

Req.get!(req, url: "https://httpbin.org/status/201?a=1")
# [info] GET https://httpbin.org/status/201 -> 201 (3ms)
```

Query strings and fragments are stripped from logged URLs.

When Req retries a request, each retry attempt is logged separately with its own duration.

## Options

### `:log_level`

Customize the log level for responses:

```elixir
req =
  Req.new()
  |> ReqLogger.attach(log_level: fn
    %Req.Response{status: status} when status >= 500 -> :error
    %Req.Response{} -> :debug
  end)
```

Failed requests are always logged as `:error`.
