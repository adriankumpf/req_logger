defmodule ReqLogger do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  require Logger

  @start_time_key :req_logger_start_time

  @levels Enum.sort(Logger.levels())

  @type opts :: [req_logger_level: Logger.level() | (Req.Response.t() -> Logger.level())]

  @doc """
  Attaches the logger to the given request.

  ## Request Options

    * `:req_logger_level` - the level to log responses at. See the module documentation.

  ## Examples

      req = Req.new() |> ReqLogger.attach()
      Req.get!(req, url: "https://httpbin.org/status/201?a=1")
      # [info] GET https://httpbin.org/status/201 -> 201 (3ms)

  """
  @spec attach(Req.Request.t(), opts()) :: Req.Request.t()
  def attach(request, opts \\ []) do
    validate_level!(opts[:req_logger_level])

    request
    |> Req.Request.register_options([:req_logger_level])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(req_logger_start_time: &start_timer/1)
    |> Req.Request.prepend_response_steps(req_logger_log_message: &log_message/1)
    |> Req.Request.prepend_error_steps(req_logger_log_message: &log_message/1)
  end

  # Validating from a request step rejects a per-request override before the request is sent.
  # Raising from the response step would discard the response the caller was about to get.
  defp start_timer(request) do
    validate_level!(Req.Request.get_option(request, :req_logger_level))

    Req.Request.put_private(request, @start_time_key, System.monotonic_time(:microsecond))
  end

  defp validate_level!(level) when is_nil(level) or is_function(level, 1) or level in @levels,
    do: :ok

  defp validate_level!(level) do
    raise ArgumentError,
          "expected :req_logger_level to be a 1-arity function or one of " <>
            "#{inspect(@levels)}, got: #{inspect(level)}"
  end

  defp log_message({request, response}) do
    level = log_level(request, response)

    # `Logger.log/2` is a macro, so the message is only built once the level passes.
    Logger.log(level, format(request, response))

    {request, response}
  end

  defp log_level(_request, exception) when is_exception(exception), do: :error

  defp log_level(request, response) do
    case Req.Request.get_option(request, :req_logger_level) do
      nil -> default_log_level(response)
      fun when is_function(fun, 1) -> fun.(response)
      level -> level
    end
  end

  defp default_log_level(%Req.Response{status: status}) when status >= 500, do: :error
  defp default_log_level(%Req.Response{status: status}) when status >= 400, do: :warning
  defp default_log_level(%Req.Response{}), do: :info

  defp format(request, response) do
    method = request.method |> to_string() |> String.upcase(:ascii)
    url = format_url(request.url)

    [method, " ", url, " -> ", format_status(response), format_duration(request)]
  end

  defp format_url(%URI{} = url) do
    URI.to_string(%{url | query: nil, fragment: nil, userinfo: nil})
  end

  defp format_status(%Req.Response{status: status}), do: Integer.to_string(status)

  defp format_status(exception) when is_exception(exception),
    do: ["error: ", Exception.message(exception)]

  # Absent when an earlier request step short-circuited before the timer ran.
  defp format_duration(request) do
    case Req.Request.get_private(request, @start_time_key) do
      nil -> []
      start -> [" (", humanize_duration(System.monotonic_time(:microsecond) - start), ")"]
    end
  end

  defp humanize_duration(us) when us < 1_000, do: "#{us}µs"
  defp humanize_duration(us) when us < 1_000_000, do: "#{div(us, 1_000)}ms"
  defp humanize_duration(us), do: "#{Float.round(us / 1_000_000, 1)}s"
end
