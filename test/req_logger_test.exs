defmodule ReqLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  @url "http://localhost"

  @duration ~r/\((\d+(?:\.\d+)?)(µs|ms|s)\)/

  setup {Req.Test, :set_req_test_from_context}
  setup {Req.Test, :verify_on_exit!}

  setup do
    {:ok, req: new_req() |> ReqLogger.attach()}
  end

  for {status, level} <- [{200, :info}, {308, :warning}, {404, :error}, {503, :error}] do
    test "logs #{status} responses at #{inspect(level)}", %{req: req} do
      expect_status(unquote(status))

      log = capture_log(fn -> Req.get(req) end)

      assert log =~ "[#{unquote(level)}] GET #{@url} -> #{unquote(status)}"
      assert log =~ @duration
    end
  end

  test "logs failed requests with log level :error", %{req: req} do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

    log = capture_log(fn -> Req.get(req) end)

    assert log =~ "[error] GET #{@url} -> error: connection refused"
    assert log =~ @duration
  end

  test "logs the request method and path", %{req: req} do
    expect_status(201)

    assert capture_log(fn -> Req.post(req, url: "/events", json: %{name: "created"}) end) =~
             "[info] POST #{@url}/events -> 201"
  end

  test "allows to configure the log level per request", %{req: req} do
    expect_status(200)

    assert capture_log(fn -> Req.get(req, log_level: &custom_log_level/1) end) =~
             "[debug] GET #{@url} -> 200"
  end

  test "allows to configure the log level when attaching the plugin" do
    expect_status(200)
    req = new_req() |> ReqLogger.attach(log_level: &custom_log_level/1)

    assert capture_log(fn -> Req.get(req) end) =~ "[debug] GET #{@url} -> 200"
  end

  test "custom log_level option is ignored for exceptions" do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))
    req = new_req() |> ReqLogger.attach(log_level: &custom_log_level/1)

    assert capture_log(fn -> Req.get(req) end) =~ "[error]"
  end

  test "strips the query string and fragment from the logged URL", %{req: req} do
    expect_status(200)

    log = capture_log(fn -> Req.get(req, url: "/search?q=secret#also-secret") end)

    assert log =~ "/search -> 200"
    refute log =~ "secret"
  end

  test "strips userinfo from the logged URL" do
    expect_status(200)
    req = new_req(base_url: "http://user:hunter2@localhost")

    log = capture_log(fn -> req |> ReqLogger.attach() |> Req.get(url: "/secrets") end)

    assert log =~ "GET #{@url}/secrets -> 200"
    refute log =~ "hunter2"
  end

  test "logs each retry attempt with its own duration" do
    Req.Test.expect(__MODULE__, 2, &Plug.Conn.resp(&1, 500, ""))
    Req.Test.expect(__MODULE__, 1, &Plug.Conn.resp(&1, 200, ""))

    # Large enough that a cumulative timer would push later attempts past it.
    retry_delay = 200

    req =
      new_req(retry: :safe_transient, retry_delay: retry_delay, max_retries: 2)
      |> ReqLogger.attach()

    lines =
      capture_log(fn -> Req.get!(req, url: "/retry") end)
      |> String.split("\n", trim: true)
      |> Enum.filter(&(&1 =~ "GET #{@url}"))

    assert Enum.count(lines, &(&1 =~ "[error]")) == 2
    assert Enum.count(lines, &(&1 =~ "[info]")) == 1

    for line <- lines, do: assert(logged_duration_us(line) < retry_delay * 1_000)
  end

  defp new_req(opts \\ []) do
    [base_url: @url, plug: {Req.Test, __MODULE__}, redirect: false, retry: false]
    |> Keyword.merge(opts)
    |> Req.new()
  end

  defp expect_status(status) do
    Req.Test.expect(__MODULE__, &Plug.Conn.resp(&1, status, ""))
  end

  defp logged_duration_us(log) do
    [_, value, unit] = Regex.run(@duration, log)
    {value, ""} = Float.parse(value)

    round(value * %{"µs" => 1, "ms" => 1_000, "s" => 1_000_000}[unit])
  end

  defp custom_log_level(%Req.Response{}), do: :debug
end
