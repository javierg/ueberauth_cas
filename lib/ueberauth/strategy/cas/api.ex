defmodule Ueberauth.Strategy.CAS.API do
  @moduledoc """
  CAS server API implementation.
  """

  alias Ueberauth.Strategy.CAS

  import SweetXml

  @doc "Validate a CAS Service Ticket with the CAS server."
  def validate_ticket(ticket, validate_url, service) do
    validate_url
    |> HTTPoison.get([], params: %{ticket: ticket, service: service}, ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 500)
    |> handle_validate_ticket_response()
  end

  defp handle_validate_ticket_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    # We catch XML parse errors, but they will still be shown in the logs.
    # See https://github.com/kbrw/sweet_xml/issues/48
    try do
      case xpath(body, ~x"//cas:serviceResponse/cas:authenticationSuccess") do
        nil -> {:error, error_from_body(body)}
        _ -> {:ok, CAS.User.from_xml(body)}
      end
    catch
      :exit, {_type, reason} -> {:error, {"malformed_xml", "Malformed XML response: #{inspect(reason)}"}}
    end
  end

  defp handle_validate_ticket_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, reason}
  end

  defp sanitize_string(value) when value == "", do: nil
  defp sanitize_string(value), do: value

  defp error_from_body(body) do
    error_code =
      xpath(body, ~x"/*/cas:authenticationFailure/@code")
      |> to_string()
      |> sanitize_string()

    message =
      xpath(body, ~x"/*/cas:authenticationFailure/text()")
      |> to_string()
      |> sanitize_string()

    {error_code || "unknown_error", message || "Unknown error"}
  end

  defp settings(key) do
    Application.get_env(:ueberauth, Ueberauth)[:providers][:cas]
    |> settings(key)
  end

  defp settings({_, values}, key), do: values[key]
  defp settings([{_, values}], key), do: values[key]
end
