defmodule ReqLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  @url "http://localhost"

  @duration ~r/\((\d+(?:\.\d+)?)(µs|ms|s)\)/

  setup {Req.Test, :set_req_test_from_context}
  setup {Req.Test, :verify_on_exit!}

  setup do
    req =
      Req.new(base_url: @url, plug: {Req.Test, __MODULE__}, redirect: false, retry: false)
      |> ReqLogger.attach()

    {:ok, req: req}
  end

  test "logs successful requests", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/health")
      end)

    assert log =~ "[info] GET #{@url}/health -> 200"
    assert_logged_duration(log)
  end

  test "logs 3xx requests with log level :warning", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 308, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[warning] GET #{@url} -> 308"
    assert_logged_duration(log)
  end

  test "logs 4xx requests with log level :error", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 404, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET #{@url} -> 404"
    assert_logged_duration(log)
  end

  test "logs 5xx requests with log level :error", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 503, ""))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET #{@url} -> 503"
    assert_logged_duration(log)
  end

  test "logs failed requests with log level :error", %{req: req} do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log(fn ->
        Req.get(req)
      end)

    assert log =~ "[error] GET #{@url} -> error: connection refused"
    assert_logged_duration(log)
  end

  test "allows to configure the log level", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    assert capture_log(fn ->
             Req.get(req, log_level: &custom_log_level/1)
           end) =~ "[debug] GET #{@url} -> 200"
  end

  test "allows to configure the log level when attaching the plugin" do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    req =
      Req.new(base_url: @url, plug: {Req.Test, __MODULE__}, redirect: false, retry: false)
      |> ReqLogger.attach(log_level: &custom_log_level/1)

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[debug] GET #{@url} -> 200"
  end

  test "strips query string from logged URL", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search?q=secret&token=abc")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
    refute log =~ "token"
  end

  test "strips fragment from logged URL", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search#secret")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
  end

  test "strips query string and fragment from logged URL", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 200, ""))

    log =
      capture_log(fn ->
        Req.get(req, url: "/search?q=secret#token")
      end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
    refute log =~ "token"
  end

  test "logs request method", %{req: req} do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, 201, ""))

    assert capture_log(fn ->
             Req.post(req, url: "/events", json: %{name: "created"})
           end) =~ "[info] POST #{@url}/events -> 201"
  end

  test "custom log_level option is ignored for exceptions" do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

    req =
      Req.new(base_url: @url, plug: {Req.Test, __MODULE__}, redirect: false, retry: false)
      |> ReqLogger.attach(log_level: fn _ -> :debug end)

    assert capture_log(fn ->
             Req.get(req)
           end) =~ "[error]"
  end

  test "logs each retry attempt with duration" do
    Req.Test.expect(__MODULE__, 2, &Plug.Conn.resp(&1, 500, ""))
    Req.Test.expect(__MODULE__, 1, &Plug.Conn.resp(&1, 200, ""))

    # A large retry delay makes the per-attempt vs. cumulative distinction observable:
    # the timer is reset at the start of each attempt (a request step re-run on every
    # retry), so no attempt's duration includes the retry sleeps that precede it.
    retry_delay = 200

    req =
      Req.new(
        base_url: @url,
        plug: {Req.Test, __MODULE__},
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
    assert log =~ @duration
  end

  defp logged_duration_us(log) do
    [_, value, unit] = Regex.run(@duration, log)

    case unit do
      "µs" -> String.to_integer(value)
      "ms" -> String.to_integer(value) * 1_000
      "s" -> round(String.to_float(value) * 1_000_000)
    end
  end

  defp req_logger_lines(log) do
    log
    |> String.split("\n", trim: true)
    |> Enum.filter(&(&1 =~ "GET #{@url}"))
  end

  defp custom_log_level(%Req.Response{}), do: :debug
end
