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
    assert_logged_duration(log)
  end

  test "logs 3xx requests with log level :warning", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 308, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[warning] GET http://localhost:#{bypass.port} -> 308"
    assert_logged_duration(log)
  end

  test "logs 4xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 404, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> 404"
    assert_logged_duration(log)
  end

  test "logs 5xx requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 503, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> 503"
    assert_logged_duration(log)
  end

  test "logs failed requests with log level :error", %{bypass: bypass, req: req} do
    Bypass.down(bypass)

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET http://localhost:#{bypass.port} -> error: connection refused"
    assert_logged_duration(log)
  end

  test "allows to configure the log level", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    assert capture_log(fn ->
             Req.get(req, log_level: &custom_log_level/1)
           end) =~ "[debug] GET http://localhost:#{bypass.port} -> 200"
  end

  test "allows to configure the log level when attaching the plugin", %{bypass: bypass} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    req =
      Req.new(base_url: "http://localhost:#{bypass.port}", redirect: false, retry: false)
      |> ReqLogger.attach(log_level: &custom_log_level/1)

    assert capture_log(fn ->
             Req.get(req)
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

  test "strips fragment from logged URL", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search#secret")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
  end

  test "strips query string and fragment from logged URL", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search?q=secret#token")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
    refute log =~ "token"
  end

  test "logs request method", %{bypass: bypass, req: req} do
    Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 201, ""))

    assert capture_log(fn ->
             Req.post(req, url: "/events", json: %{name: "created"})
           end) =~ "[info] POST http://localhost:#{bypass.port}/events -> 201"
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

    # A large retry delay makes the per-attempt vs. cumulative distinction observable:
    # the timer is reset at the start of each attempt (a request step re-run on every
    # retry), so no attempt's duration includes the retry sleeps that precede it.
    retry_delay = 200

    req =
      Req.new(
        base_url: "http://localhost:#{bypass.port}",
        redirect: false,
        retry: :safe_transient,
        retry_delay: retry_delay,
        max_retries: 2
      )
      |> ReqLogger.attach()

    log =
      capture_log(fn ->
        Req.get!(req, url: "/retry")
      end)

    req_logger_lines = req_logger_lines(log)

    error_lines = Enum.filter(req_logger_lines, &(&1 =~ "[error]"))
    info_lines = Enum.filter(req_logger_lines, &(&1 =~ "[info]"))

    assert length(error_lines) == 2
    assert length(info_lines) == 1

    # Every attempt (including the 2nd and 3rd, which follow one and two retry sleeps
    # respectively) must report a per-attempt duration far below a single retry delay.
    # A cumulative timer would push those later attempts past `retry_delay`.
    for line <- req_logger_lines do
      assert_logged_duration(line)
      assert logged_duration_us(line) < retry_delay * 1_000
    end
  end

  defp assert_logged_duration(log) do
    assert log =~ ~r/\(\d+(µs|ms|\d+\.\ds)\)(\e\[0m)?/
  end

  defp logged_duration_us(log) do
    [_, value, unit] = Regex.run(~r/\((\d+(?:\.\d+)?)(µs|ms|s)\)/, log)

    case unit do
      "µs" -> String.to_integer(value)
      "ms" -> String.to_integer(value) * 1_000
      "s" -> round(String.to_float(value) * 1_000_000)
    end
  end

  defp req_logger_lines(log) do
    log
    |> String.split("\n", trim: true)
    |> Enum.filter(&(&1 =~ "GET http://localhost:"))
  end

  defp custom_log_level(%Req.Response{}), do: :debug
end
