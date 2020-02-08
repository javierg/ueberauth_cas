defmodule Ueberauth.Strategy.CAS.API do
  @moduledoc """
  CAS server API implementation.
  """

  use Ueberauth.Strategy
  alias Ueberauth.Strategy.CAS

  @doc "Returns the URL to this CAS server's login page."
  def login_url do
    settings(:base_url) <> "/login"
  end

  @doc "Validate a CAS Service Ticket with the CAS server."
  def validate_ticket(ticket, conn) do
    HTTPoison.get(validate_url, [], params: %{ticket: ticket, service: callback_url(conn)}, ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 500)
    |> handle_validate_ticket_response
  end

  defp handle_validate_ticket_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    case String.match?(body, ~r/cas:authenticationFailure/) do
      true -> {:error, error_from_body(body)}
      _    -> {:ok, CAS.User.from_xml(body)}
    end
  end

  defp handle_validate_ticket_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, reason}
  end

  defp error_from_body(body) do
    case Regex.named_captures(~r/code="(?<code>\w+)"/, body) do
      %{"code" => code} -> code
      _                 -> "UNKNOWN_ERROR"
    end
  end

  defp validate_url do
    settings(:base_url) <> "/serviceValidate"
  end

  defp settings(key) do
    Application.get_env(:ueberauth, Ueberauth)[:providers][:cas]
    |> settings(key)
  end

  defp settings({_, values}, key), do: values[key]
  defp settings([{_, values}], key), do: values[key]
end
