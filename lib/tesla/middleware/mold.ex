defmodule Tesla.Middleware.Mold do
  @moduledoc """
  Tesla middleware that validates response status codes and parses response bodies
  against [Mold](https://hex.pm/packages/mold) schemas declared at the call site.

  See the [Mold pattern guide](https://hexdocs.pm/mold/using-with-http-clients.html)
  for the reasoning behind this approach.

  ## Usage

  Add the middleware to your Tesla client after `Tesla.Middleware.Telemetry` (so
  failures end up in the request's telemetry metadata) and before
  `Tesla.Middleware.JSON` (so the body is already decoded when Mold sees it):

      def client do
        Tesla.client([
          {Tesla.Middleware.BaseUrl, "https://api.example.com"},
          {Tesla.Middleware.Telemetry, metadata: %{service: :example}},
          Tesla.Middleware.Mold,
          Tesla.Middleware.JSON
        ])
      end

  Declare the expected responses per call via `opts: [mold: %{...}]`:

      defmodule MyApp.UsersAPI do
        defp user_schema do
          %{
            id: :integer,
            name: :string,
            email: :string,
            created_at: :datetime
          }
        end

        def get_user(id) do
          case Tesla.get!(client(), "/users/\#{id}",
                 opts: [mold: %{200 => user_schema(), 404 => nil}]
               ) do
            %Tesla.Env{status: 200, body: user} -> user
            %Tesla.Env{status: 404} -> nil
          end
        end

        def post_event(payload) do
          case Tesla.post(client(), "/events", payload, opts: [mold: %{204 => nil}]) do
            {:ok, _env} -> :ok
            {:error, _} -> {:error, :service_unavailable}
          end
        end

        defp client do
          Tesla.client([
            {Tesla.Middleware.BaseUrl, "https://api.example.com"},
            {Tesla.Middleware.Telemetry, metadata: %{service: :users_api}},
            Tesla.Middleware.Mold,
            Tesla.Middleware.JSON
          ])
        end
      end

  The two functions illustrate the two common shapes for integration code:

  - `get_user/1` follows the same shape as `Ecto.Repo.get/2`: it returns
    `nil | term` and raises on everything else. `404` is a normal business answer
    (the record isn't there, return `nil`). A network error, an unexpected
    status, or a schema mismatch raises. The integration code assumes
    infrastructure works, just like database code does, and the exception
    bubbles up to the top-level handler, whether a Phoenix controller, an Oban
    job, or similar.
  - `post_event/1` keeps the tagged-tuple shape and translates the middleware's
    internal error into a stable, app-level reason (`:service_unavailable`).
    This is the right choice when the caller needs to handle infrastructure
    failures gracefully rather than propagate them: e.g. a GraphQL resolver
    where an unhandled exception would fail the entire query, or a place that
    falls back to a cached value when the remote service is down. The raw error
    struct doesn't leak past the module boundary.

  Neither function looks at the error struct's fields (`expected_statuses`,
  `status`, `body`, `errors`), and that's fine: `Tesla.Middleware.Telemetry`
  surfaces them automatically. When the middleware fails a request, Tesla fires
  its standard `[:tesla, :request, :stop]` event with the error as the result,
  and any handler already wired to that event picks up the full details with no
  integration-specific code.

  `Tesla.get!` in `get_user/1` additionally wraps the error into a `Tesla.Error`,
  so the same details show up in stacktraces automatically. Surfacing them to an
  end user is a separate step: pattern-match on the error where you call the
  integration and map it to whatever the UI expects.

  ## The mold option

  A map from HTTP status code to either a Mold schema or `nil`:

  - **Status not in the map**: request fails with `Tesla.Middleware.Mold.UnexpectedStatusError`.
  - **Schema is `nil`**: response is accepted as-is and the body is not parsed.
    Use for `204 No Content`, for `404` when only presence/absence matters, and
    for responses whose body you don't want parsed at all (binary download,
    stream, redirect).
  - **Schema is a Mold type**: body is passed to `Mold.parse/2`. On success the
    parsed value replaces `env.body`. On failure the request fails with
    `Tesla.Middleware.Mold.ParseError`.

  When the `:mold` option is absent, the middleware is a no-op.

  See the [Mold formatting errors guide](https://hexdocs.pm/mold/formatting-errors.html)
  for turning `%Mold.Error{}` into user-visible messages.
  """

  @behaviour Tesla.Middleware

  defmodule ParseError do
    @moduledoc """
    Error returned by `Tesla.Middleware.Mold` when a Mold schema rejects the
    response body.
    """

    @enforce_keys [:status, :errors]
    defstruct [:status, :errors, :body]

    @type t :: %__MODULE__{status: non_neg_integer(), errors: [Mold.Error.t()], body: any()}

    defimpl Inspect do
      import Inspect.Algebra

      def inspect(error, opts) do
        opts = %{opts | pretty: true}

        entries = [
          concat("status: ", to_doc(error.status, opts)),
          concat("errors: ", format_errors(error.errors, opts)),
          concat("body: ", to_doc(error.body, opts))
        ]

        container_doc("#Tesla.Middleware.Mold.ParseError<", entries, ">", opts, fn doc, _opts ->
          doc
        end)
        |> format(opts.width)
        |> IO.iodata_to_binary()
      end

      defp format_errors(errors, opts) do
        formatted = errors |> List.wrap() |> Enum.map(&to_doc(&1, opts))
        container_doc("[", formatted, "]", opts, fn doc, _opts -> doc end)
      end
    end
  end

  defmodule UnexpectedStatusError do
    @moduledoc """
    Error returned by `Tesla.Middleware.Mold` when the response status is not
    in the `:mold` option map.
    """

    @enforce_keys [:status, :expected_statuses]
    defstruct [:status, :expected_statuses, :body]

    @type t :: %__MODULE__{
            status: non_neg_integer(),
            expected_statuses: [non_neg_integer()],
            body: any()
          }

    defimpl Inspect do
      import Inspect.Algebra

      def inspect(error, opts) do
        opts = %{opts | pretty: true}

        entries = [
          concat("status: ", to_doc(error.status, opts)),
          concat("expected: ", to_doc(error.expected_statuses, opts)),
          concat("body: ", to_doc(error.body, opts))
        ]

        container_doc(
          "#Tesla.Middleware.Mold.UnexpectedStatusError<",
          entries,
          ">",
          opts,
          fn doc, _opts -> doc end
        )
        |> format(opts.width)
        |> IO.iodata_to_binary()
      end
    end
  end

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    with {:ok, env} <- Tesla.run(env, next) do
      case Keyword.fetch(env.opts, :mold) do
        {:ok, schemas} -> parse_response(env, schemas)
        :error -> {:ok, env}
      end
    end
  end

  defp parse_response(env, schemas) do
    case Map.fetch(schemas, env.status) do
      {:ok, nil} ->
        {:ok, env}

      {:ok, schema} ->
        case Mold.parse(schema, env.body) do
          {:ok, parsed} ->
            {:ok, %{env | body: parsed}}

          {:error, errors} ->
            {:error, %ParseError{status: env.status, errors: errors, body: env.body}}
        end

      :error ->
        {:error,
         %UnexpectedStatusError{
           status: env.status,
           expected_statuses: Map.keys(schemas),
           body: env.body
         }}
    end
  end
end
