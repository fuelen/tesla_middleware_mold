defmodule Tesla.Middleware.MoldTest do
  use ExUnit.Case, async: true

  alias Tesla.Middleware.Mold.{ParseError, UnexpectedStatusError}

  defp client(adapter_fun) do
    Tesla.client([Tesla.Middleware.Mold], adapter_fun)
  end

  defp adapter_with(status, body) do
    fn %Tesla.Env{} = env -> {:ok, %{env | status: status, body: body}} end
  end

  describe "without :mold option" do
    test "passes the response through untouched" do
      client = client(adapter_with(200, %{"id" => 1}))
      assert {:ok, %Tesla.Env{status: 200, body: %{"id" => 1}}} = Tesla.get(client, "/")
    end
  end

  describe "with :mold option" do
    test "nil schema accepts the response without parsing the body" do
      client = client(adapter_with(204, "ignored"))

      assert {:ok, %Tesla.Env{status: 204, body: "ignored"}} =
               Tesla.get(client, "/", opts: [mold: %{204 => nil}])
    end

    test "Mold schema parses and replaces the body on success" do
      client = client(adapter_with(200, %{"id" => "1", "name" => "Alice"}))
      schema = %{id: :integer, name: :string}

      assert {:ok, %Tesla.Env{status: 200, body: %{id: 1, name: "Alice"}}} =
               Tesla.get(client, "/", opts: [mold: %{200 => schema}])
    end

    test "returns ParseError when Mold.parse/2 fails" do
      raw = %{"id" => "not-an-integer"}
      client = client(adapter_with(200, raw))
      schema = %{id: :integer}

      assert {:error, %ParseError{status: 200, body: ^raw, errors: [%Mold.Error{} | _]}} =
               Tesla.get(client, "/", opts: [mold: %{200 => schema}])
    end

    test "returns UnexpectedStatusError when status is not in the map" do
      client = client(adapter_with(500, "boom"))

      assert {:error,
              %UnexpectedStatusError{
                status: 500,
                expected_statuses: expected,
                body: "boom"
              }} = Tesla.get(client, "/", opts: [mold: %{200 => %{id: :integer}, 404 => nil}])

      assert Enum.sort(expected) == [200, 404]
    end
  end

  describe "error structs" do
    test "ParseError inspect output" do
      error = %ParseError{
        status: 422,
        errors: [%Mold.Error{reason: :unexpected_nil, value: nil, trace: [:name]}],
        body: %{"name" => nil}
      }

      assert inspect(error) == """
             #Tesla.Middleware.Mold.ParseError<
               status: 422,
               errors: [%Mold.Error{reason: :unexpected_nil, value: nil, trace: [:name]}],
               body: %{"name" => nil}
             >\
             """
    end

    test "UnexpectedStatusError inspect output" do
      error = %UnexpectedStatusError{status: 500, expected_statuses: [200, 404], body: "boom"}

      assert inspect(error) == """
             #Tesla.Middleware.Mold.UnexpectedStatusError<
               status: 500,
               expected: [200, 404],
               body: "boom"
             >\
             """
    end
  end
end
