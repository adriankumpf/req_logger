defmodule ReqLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  setup do
    bypass = Bypass.open()

    req =
      Req.new(base_url: "http://localhost:#{bypass.port}", redirect: false, retry: false)
      |> ReqLogger.attach()

    {:ok, bypass: bypass, req: req}
  end

  test "logs successful requests", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    assert capture_log(fn ->
             Req.get(req, url: "/health")
           end) =~ "[info] GET http://localhost:#{bypass.port}/health -> 200"
  end

  test "logs 3xx requests with log level :warn", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 308, ""))

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[warning] GET http://localhost:#{bypass.port} -> 308"
  end

  test "logs 4xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 404, ""))

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[error] GET http://localhost:#{bypass.port} -> 404"
  end

  test "logs 5xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 503, ""))

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[error] GET http://localhost:#{bypass.port} -> 503"
  end

  test "logs failed requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.down(bypass)

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[error] GET http://localhost:#{bypass.port} -> error: connection refused"
  end

  test "allows to configure the log level", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    assert capture_log(fn ->
             Req.get(req, log_level: &custom_log_level/1)
           end) =~ "[debug] GET http://localhost:#{bypass.port} -> 200"
  end

  defp custom_log_level(%Req.Response{}), do: :debug
end
