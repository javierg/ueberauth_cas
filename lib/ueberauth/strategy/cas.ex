defmodule Ueberauth.Strategy.CAS do
  @moduledoc """
  CAS Strategy for Überauth. Redirects the user to a CAS login page
  and verifies the Service Ticket the CAS server returns after a
  successful login.

  The login flow looks like this:

  1. User is redirected to the CAS server's login page by
    `Ueberauth.Strategy.CAS.handle_request!/1`

  2. User signs in to the CAS server.

  3. CAS server redirects back to the Elixir application, sending
    a Service Ticket in the URL parameters.

  4. This Service Ticket is validated by this Überauth CAS strategy,
    fetching the user's information at the same time.

  5. User can proceed to use the Elixir application.

  ## Protocol compliance

  This strategy only supports a subset of the CAS protocol (version 2.0 and 3.0).
  Notable, there is no support for proxy-related stuff.

  More specifically, it supports following CAS URIs:

  - `/login`

     The strategy supports calling `/login` to enable the user to login.
     This is known as the [credential requestor][login]
     mode in the CAS specification.

    The strategy only supports the `service` parameter, and currently does
    not provide support for `renew`, `gateway` or `method`.

  - `/serviceValidate`

    After a successful login, the strategy validates the ticket and retrieves
    information about the user, as described in the [specification][validate].
    
    The strategy only supports the required params, `service` and `ticket`.
    There is no support for other params.

  ## Errors

  If the login fails, the strategy will fail with error key `missing_ticket`.

  If the ticket validation fails, the error key depends:

  - If the response is no valid XML, the error key is `malformed_xml`.
  - If there is proper error code in the CAS serviceResponse, the error code will
    be used as error key, while the description will be used as error message.
  - In other cases, the error key will be `unknown_error`.

  ## User data

  In the ticket validation step (step 4), user information is retrieved.
  See `Ueberauth.Strategy.CAS.User` for documentation on which CAS attributes
  are mapped to which Überauth attribute.

  [login]: https://apereo.github.io/cas/6.2.x/protocol/CAS-Protocol-Specification.html#21-login-as-credential-requestor
  [validate]: https://apereo.github.io/cas/6.2.x/protocol/CAS-Protocol-Specification.html#25-servicevalidate-cas-20
  """

  use Ueberauth.Strategy

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Strategy.CAS

  @doc """
  Ueberauth `request` handler. Redirects to the CAS server's login page.
  """
  def handle_request!(conn) do
    conn
    |> redirect!(redirect_url(conn))
  end

  @doc """
  Ueberauth after login callback with a valid CAS Service Ticket.
  """
  def handle_callback!(%Plug.Conn{params: %{"ticket" => ticket}} = conn) do
    conn
    |> handle_ticket(ticket)
  end

  @doc """
  Ueberauth after login callback missing a CAS Service Ticket.
  """
  def handle_callback!(conn) do
    conn
    |> set_errors!([error("missing_ticket", "No service ticket received")])
  end

  @doc """
  Ueberauth cleanup callback. Clears CAS session information from `conn`.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:cas_ticket, nil)
    |> put_private(:cas_user, nil)
  end

  @doc "Ueberauth UID callback."
  def uid(conn), do: conn.private.cas_user.email

  @doc """
  Ueberauth extra information callback. Returns all information the CAS
  server returned about the user that authenticated.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        user: conn.private.cas_user
      }
    }
  end

  @doc """
  Ueberauth user information.
  """
  def info(conn) do
    user = conn.private.cas_user

    %Info{
      name: user.name,
      email: user.email
    }
  end

  @doc """
  Ueberauth credentials callback. Contains CAS Service Ticket and user roles.
  """
  def credentials(conn) do
    %Credentials{
      expires: false,
      token: conn.private.cas_ticket,
      other: conn.private.cas_user.roles
    }
  end

  defp redirect_url(conn) do
    CAS.API.login_url() <> "?service=#{callback_url(conn)}"
  end

  defp handle_ticket(conn, ticket) do
    conn
    |> put_private(:cas_ticket, ticket)
    |> fetch_user(ticket)
  end

  defp fetch_user(conn, ticket) do
    ticket
    |> CAS.API.validate_ticket(conn)
    |> handle_validate_ticket_response(conn)
  end

  defp handle_validate_ticket_response({:error, {code, message}}, conn) do
    conn
    |> set_errors!([error(code, message)])
  end

  defp handle_validate_ticket_response({:ok, %CAS.User{} = user}, conn) do
    conn
    |> put_private(:cas_user, user)
  end
end
