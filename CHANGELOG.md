# Changelog

## v0.2.0 (2026-08-12)

First release published to Hex. Earlier versions were installed from git.

### Breaking changes

- Require Elixir 1.16 or later, up from 1.15.
- Require Req 0.7 or later, up from 0.5. Req 0.5 and 0.6 skipped the request steps when the
  retry or redirect step re-entered the pipeline, so the timer was never restarted and every
  attempt after the first reported a cumulative duration that included the retry delay.
- Renamed the `:log_level` option to `:req_logger_level`. Req keeps every option in one flat
  namespace shared by all plugins and does not detect collisions when registering them, so two
  plugins claiming `:log_level` would silently share a value. Passing `:log_level` now raises
  `unknown option :log_level`.
- Reworked the default log levels to `:error` for 5xx responses, `:warning` for 4xx responses
  and `:info` for everything else, replacing `:error` for anything 4xx and above and `:warning`
  for 3xx. Req follows redirects by default, so a redirect it resolved on its own warned about
  entirely routine traffic, and a 404 is frequently the expected answer rather than a failure.

### Added

- `:req_logger_level` accepts a `t:Logger.level/0` atom in addition to a function, matching how
  Req's own `:retry_log_level` and `:redirect_log_level` work.
- Invalid `:req_logger_level` values raise `ArgumentError` when the plugin is attached, or —
  for a per-request override — before the request is sent. Previously anything that was not a
  1-arity function was silently ignored and the default level was used instead.

### Fixed

- Strip userinfo from logged URLs. A base URL carrying credentials logged them verbatim:
  `GET http://user:hunter2@localhost/secrets -> 200`. Query strings and fragments were already
  stripped.
- Omit the duration, rather than raising `KeyError`, when an earlier request step
  short-circuits before the start-time step runs. A cache, a mock or a circuit breaker
  returning a canned response skips the timer, and the logger then replaced the caller's
  actual result with a `KeyError`.

## v0.1.0 (2023-09-16)

Initial release.
