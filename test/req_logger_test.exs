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

    log =
      capture_log(fn ->
        Req.get(req, url: "/health")
      end)

    assert log =~ "[info] GET http://localhost:#{bypass.port}/health -> 200"
    assert log =~ ~r/200 \(\d+(µs|ms|\d+\.\ds)\)/
  end

  test "logs 3xx requests with log level :warn", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 308, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[warning] GET http://localhost:#{bypass.port} -> 308"
    assert log =~ ~r/308 \(\d+(µs|ms|\d+\.\ds)\)/
  end

  test "logs 4xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 404, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> 404"
    assert log =~ ~r/404 \(\d+(µs|ms|\d+\.\ds)\)/
  end

  test "logs 5xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 503, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> 503"
    assert log =~ ~r/503 \(\d+(µs|ms|\d+\.\ds)\)/
  end

  test "logs failed requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.down(bypass)

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> error: connection refused"
    assert log =~ ~r/connection refused \(\d+(µs|ms|\d+\.\ds)\)/
  end

  test "allows to configure the log level", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    assert capture_log(fn ->
             Req.get(req, log_level: &custom_log_level/1)
           end) =~ "[debug] GET http://localhost:#{bypass.port} -> 200"
  end

  test "strips query string from logged URL", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search?q=secret&token=abc")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
    refute log =~ "token"
  end

  test "custom log_level option is ignored for exceptions", %{bypass: bypass} do
    Bypass.down(bypass)

    req =
      Req.new(base_url: "http://localhost:#{bypass.port}", redirect: false, retry: false)
      |> ReqLogger.attach(log_level: fn _ -> :debug end)

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[error]"
  end

  test "logs each retry attempt with duration", %{bypass: bypass} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, fn conn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if n < 3 do
        Plug.Conn.resp(conn, 500, "")
      else
        Plug.Conn.resp(conn, 200, "")
      end
    end)

    req =
      Req.new(
        base_url: "http://localhost:#{bypass.port}",
        redirect: false,
        retry: :safe_transient,
        retry_delay: 10,
        max_retries: 2
      )
      |> ReqLogger.attach()

    log =
      capture_log(fn ->
        Req.get!(req, url: "/retry")
      end)

    lines = String.split(log, "\n", trim: true)

    req_logger_lines = Enum.filter(lines, &(&1 =~ "GET http://localhost:"))

    error_lines = Enum.filter(req_logger_lines, &(&1 =~ "[error]"))
    info_lines = Enum.filter(req_logger_lines, &(&1 =~ "[info]"))

    assert length(error_lines) == 2
    assert length(info_lines) == 1

    for line <- req_logger_lines do
      assert line =~ ~r/\(\d+(µs|ms|\d+\.\ds)\)(\e\[0m)?$/
    end
  end

  defp custom_log_level(%Req.Response{}), do: :debug
end
