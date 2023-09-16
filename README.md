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
  {:req, "~> 0.4.3"},
  {:req_logger, "~> 0.1.0", github: "adriankumpf/req_logger"}
])

req =
  Req.new()
  |> ReqLogger.attach()

Req.get!(req, url: "https://httpbin.org/status/201?a=1")
# [info] GET https://httpbin.org/status/201 -> 201
```
