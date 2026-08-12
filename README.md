# ReqLogger

[![CI](https://github.com/adriankumpf/req_logger/actions/workflows/ci.yml/badge.svg)](https://github.com/adriankumpf/req_logger/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/req_logger.svg)](https://hex.pm/packages/req_logger)
[![Documentation](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/req_logger)

[Req](https://github.com/wojtekmach/req) Logger plugin.

## Installation

```elixir
def deps do
  [
    {:req_logger, "~> 0.2.0"}
  ]
end
```

The documentation is available on [HexDocs](https://hexdocs.pm/req_logger).

<!-- MDOC !-->

Logs the request method, URL, response status and duration with Elixir's Logger.

```elixir
req =
  Req.new()
  |> ReqLogger.attach()

Req.get!(req, url: "https://httpbin.org/status/201?a=1")
# [info] GET https://httpbin.org/status/201 -> 201 (3ms)
```

Query strings, fragments and userinfo are stripped from logged URLs to avoid logging common
places for sensitive values.

When Req retries a request, each attempt is logged separately with its own duration.

## Options

### `:req_logger_level`

Either a `t:Logger.level/0`:

```elixir
req =
  Req.new()
  |> ReqLogger.attach(req_logger_level: :debug)
```

or a function that receives the `Req.Response` and returns one:

```elixir
req =
  Req.new()
  |> ReqLogger.attach(req_logger_level: fn
    %Req.Response{status: status} when status >= 500 -> :error
    %Req.Response{} -> :debug
  end)
```

Defaults to `:error` for 5xx responses, `:warning` for 4xx responses and `:info` for everything
else. Failed requests are always logged as `:error`, regardless of this option.

Invalid values raise an `ArgumentError` when the plugin is attached, or — for a per-request
override — before the request is sent.
