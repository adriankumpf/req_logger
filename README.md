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

Either a `t:Logger.level/0` or a function that receives the `Req.Response` and returns one.

Defaults to `:info` for 2xx responses, `:warning` for 3xx responses and `:error` for 4xx and
5xx responses. Failed requests are always logged as `:error`, regardless of this option.

```elixir
req =
  Req.new()
  |> ReqLogger.attach(req_logger_level: fn
    %Req.Response{status: status} when status >= 500 -> :error
    %Req.Response{} -> :debug
  end)
```

Invalid values raise an `ArgumentError` when the plugin is attached, or — for a per-request
override — before the request is sent.
