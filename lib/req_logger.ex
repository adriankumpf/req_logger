defmodule ReqLogger do
  @moduledoc """
  `Req` Logger plugin.

  Logs the request method, URL, response status and duration with Elixir's Logger.

  Query strings and URL fragments are stripped from logged URLs to avoid logging common places
  for sensitive values.

  When Req retries a request, each retry attempt is logged separately.

  ## Options

  - `:log_level` - custom function that receives the `Req.Response` for calculating log level.
    Defaults to `:info` for 2xx responses, `:warning` for 3xx responses and `:error` for 4xx and
    5xx responses. Failed requests are always logged as `:error`.

  """

  require Logger

  @start_time_key :req_logger_start_time

  @type log_level_fun :: (Req.Response.t() -> Logger.level())
  @type log_level_option :: {:log_level, log_level_fun()}
  @type opts :: [log_level_option()]

  @doc """
  Runs the plugin.

  ## Examples

      iex> req = Req.new() |> ReqLogger.attach()
      iex> Req.get!(req, url: "https://httpbin.org/status/201?a=1")
      # [info] GET https://httpbin.org/status/201 -> 201 (3ms)

  """
  @spec attach(Req.Request.t(), opts()) :: Req.Request.t()
  def attach(request, opts \\ []) do
    request
    |> Req.Request.register_options([:log_level])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(req_logger_start_time: &put_start_time/1)
    |> Req.Request.prepend_response_steps(req_logger_log_message: &log_message/1)
    |> Req.Request.prepend_error_steps(req_logger_log_message: &log_message/1)
  end

  defp put_start_time(request) do
    Req.Request.put_private(request, @start_time_key, System.monotonic_time())
  end

  defp log_message({request, response}) do
    level = log_level(response, request.options)
    start = Map.fetch!(request.private, @start_time_key)
    duration = System.monotonic_time() - start

    # `Logger.log/2` is a macro, so the message is only built once the level passes.
    Logger.log(level, format(request, response, duration))

    {request, response}
  end

  defp format(request, response, duration) do
    method = request.method |> to_string() |> String.upcase()
    url = format_url(request.url)

    [method, " ", url, " -> ", format_status(response), " (", format_duration(duration), ")"]
  end

  defp format_url(%URI{} = url) do
    %URI{url | query: nil, fragment: nil}
    |> URI.to_string()
  end

  defp format_status(%Req.Response{status: status}), do: Integer.to_string(status)

  defp format_status(exception) when is_exception(exception),
    do: ["error: ", Exception.message(exception)]

  defp format_duration(duration_native) do
    duration_us = System.convert_time_unit(duration_native, :native, :microsecond)

    cond do
      duration_us < 1_000 -> "#{duration_us}µs"
      duration_us < 1_000_000 -> "#{div(duration_us, 1_000)}ms"
      true -> "#{Float.round(duration_us / 1_000_000, 1)}s"
    end
  end

  defp log_level(exception, _opts) when is_exception(exception), do: :error
  defp log_level(response, %{log_level: fun}) when is_function(fun, 1), do: fun.(response)
  defp log_level(response, _opts), do: default_log_level(response)

  defp default_log_level(%Req.Response{} = res) when res.status >= 400, do: :error
  defp default_log_level(%Req.Response{} = res) when res.status >= 300, do: :warning
  defp default_log_level(%Req.Response{}), do: :info
end
