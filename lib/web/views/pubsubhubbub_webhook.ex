defmodule Bonfire.RSS.PubSubHubbub.WebhookController do
  use Bonfire.UI.Common.Web, :controller

  # Handle subscription verification
  def callback(conn, %{"hub.mode" => mode, "hub.challenge" => challenge} = _params)
      when mode in ["subscribe", "unsubscribe"] do
    # Verify hub.verify_token if you set one
    # params["hub.verify_token"]

    text(conn, challenge)
  end

  def callback(conn, params) do
    debug(params, "Request not supported")
    text(conn, "Request not supported")
  end

  def posted(conn, %{"hub.mode" => _, "hub.challenge" => _} = params) do
    callback(conn, params)
  end

  # Handle feed updates
  def posted(conn, _params) do
    {:ok, body, conn} = read_body(conn)
    # Process the update notification...
    Bonfire.RSS.parse(body)
    |> debug(body)
    ~> Bonfire.RSS.Integration.process_and_save(fetch_items: true)

    send_resp(conn, 200, "OK")
  end
end
