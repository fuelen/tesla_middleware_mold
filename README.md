# Tesla.Middleware.Mold

[Tesla](https://hex.pm/packages/tesla) middleware that validates response status
codes and parses response bodies against [Mold](https://hex.pm/packages/mold)
schemas declared at the call site.

```elixir
Tesla.get(client, "/users/#{id}", opts: [mold: %{200 => user_schema(), 404 => nil}])
```

A `200` with the declared shape is accepted, `404` is accepted without parsing
the body, anything else fails the request. Because the check runs inside the
Tesla middleware chain, unexpected statuses and schema mismatches become failed
requests in Tesla's telemetry events, not silent problems surfacing later.

## Installation

```elixir
def deps do
  [
    {:tesla_middleware_mold, "~> 0.1"}
  ]
end
```

## Documentation

Full docs at
[hexdocs.pm/tesla_middleware_mold](https://hexdocs.pm/tesla_middleware_mold).
The [Mold pattern guide](https://hexdocs.pm/mold/using-with-http-clients.html)
explains the reasoning behind the approach.

## License

Apache-2.0
