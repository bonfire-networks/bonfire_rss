defmodule Bonfire.RSS.PubSubHubbub do
  @moduledoc """
  An Elixir client for PubSubHubbub (now known as WebSub).

  PubSubHubbub is a simple, open, server-to-server webhook-based publish/subscribe protocol.
  This module provides functionality to subscribe to and unsubscribe from RSS/Atom feeds 
  through a hub.

  ## Features

  - Subscribe to topic feeds through a PubSubHubbub hub
  - Unsubscribe from topic feeds
  - Find RSS feeds using Google's Feed API
  - Support for authentication credentials (e.g., for SuperFeedr)
  - Configurable verification mode and lease duration
  - Built with Req for modern HTTP handling

  ## Basic Usage

  First, create a new subscriber with your hub URL and callback URL:

  ```elixir
  alias Bonfire.RSS.PubSubHubbub

  webhook_url = "https://#{System.get_env("TUNNEL_DOMAIN")}/bonfire_rss/webhook" # Your app's callback URL

  subscribe_url = "https://websub.rocks/blog/103/B4nmEcj0StfDnn9NEUb3"
  # or atom: "https://websub.rocks/blog/103/B4nmEcj0StfDnn9NEUb3"

  # Discover the feed's hub
  {:ok, %{hub: hub, self_link: self}} = PubSubHubbub.discover(subscribe_url)

  # Create a new subscriber
  subscriber = PubSubHubbub.new(
    hub || "https://websubhub.com/hub",  # Hub URL
    webhook_url
  )

  # Subscribe to a feed
  {:ok, _} = PubSubHubbub.subscribe(subscriber, subscribe_url)

  # Unsubscribe from a feed
  {:ok, _} = PubSubHubbub.unsubscribe(subscriber, subscribe_url)
  ```

  ## Advanced Usage

  ### Authentication (e.g., for SuperFeedr)

  ```elixir
  # Create an authenticated subscriber
  subscriber = PubSubHubbub.new(
    "http://pubsubhubbub.superfeedr.com",
    "https://myapp.com/hub-callback",
    "username:password"  # Basic auth credentials
  )
  ```

  ### Configuring Subscription Options

  ```elixir
  # Configure verification mode and lease duration
  subscriber = %PubSubHubbub{
    subscriber |
    verify: "sync",                # "sync" or "async"
    verify_token: "your-token",    # For verification
    lease_seconds: 86400          # 24 hours
  }
  ```

  ## Implementing the Callback Endpoint

  Your callback URL needs to handle both GET (for verification) and POST (for updates) requests. Here's an example using Phoenix:

  ```elixir
  defmodule MyApp.HubController do
    use MyApp.Web, :controller

    # Handle subscription verification
    def callback(conn, %{"hub.mode" => mode, "hub.challenge" => challenge} = params)
        when mode in ["subscribe", "unsubscribe"] do
      # Verify hub.verify_token if you set one
      # params["hub.verify_token"]
      
      text(conn, challenge)
    end

    # Handle feed updates
    def callback(conn, _params) do
      {:ok, body, conn} = read_body(conn)
      # Process the update notification...
      
      send_resp(conn, 200, "OK")
    end
  end
  ```

  """

  use Untangle

  @doc """
  Creates a new Subscriber struct with the given hub URL and callback URL.

  ## Parameters

  - `hub_url`: The URL of the PubSubHubbub hub
  - `callback_url`: Your application's callback URL where updates will be received
  - `credentials`: Optional authentication credentials for services like SuperFeedr

  ## Examples

      iex> subscriber = new("http://hub.example.com", "http://callback.example.com")
      iex> subscriber.hub_url
      "http://hub.example.com"

      iex> subscriber = new("http://hub.example.com", "http://callback.example.com", "user:pass")
      iex> subscriber.credentials
      "user:pass"

      iex> new("not-a-url", "http://callback.example.com")
      ** (ArgumentError) The specified hub url does not appear to be valid: not-a-url

      iex> new(nil, "http://callback.example.com")
      ** (ArgumentError) Please specify a hub url
  """
  defstruct hub_url: nil,
            callback_url: nil,
            credentials: nil,
            verify: "async",
            verify_token: nil,
            lease_seconds: nil

  @type t :: %__MODULE__{
          hub_url: String.t(),
          callback_url: String.t(),
          credentials: String.t() | nil,
          verify: String.t(),
          verify_token: String.t() | nil,
          lease_seconds: integer() | nil
        }

  @doc """
  # Usage Example
  ```
  subscribe_url = "https://example.com/feed"
  case discover(feed_url) do
    {:ok, %{hub: hub, self_link: self}} ->
      new(hub, callback_url)

    {:error, reason} ->
      IO.puts(reason)
  end
  ```
  """
  def discover(feed_url) do
    opts =
      [headers: [{"Accept", "application/rss+xml, application/xml"}]]
      |> Keyword.merge(Application.get_env(:bonfire_rss, :req_options, []))

    {:ok, response} =
      Req.get(feed_url, opts)

    case response do
      %Req.Response{status: 200, body: body, headers: headers} ->
        # Try to extract hub and self URLs from headers first, then body
        case {extract_hub(headers, body), extract_self(headers, body)} do
          {nil, _} ->
            {:error, "No hub found"}

          {hub, nil} ->
            IO.puts("No self link found")
            {:ok, %{hub: hub}}

          {hub, self_link} ->
            {:ok, %{hub: hub, self_link: self_link}}
        end

      %Req.Response{status: status} ->
        {:error, "Failed to fetch feed. Status: #{status}"}
    end
  end

  # Extract hub URL from headers or fallback to body
  defp extract_hub(headers, body) do
    headers
    |> find_link("hub")
    |> case do
      nil -> extract_link_from_body(body, "hub")
      hub -> hub
    end
  end

  # Extract self URL from headers or fallback to body
  defp extract_self(headers, body) do
    headers
    |> find_link("self")
    |> case do
      nil -> extract_link_from_body(body, "self")
      self_link -> self_link
    end
  end

  # Parse the HTTP Link headers to find a URL with the given rel attribute
  defp find_link(headers, rel) do
    headers
    |> Enum.find_value(fn
      {"link", value} ->
        parse_link_header(value, rel)

      _ ->
        nil
    end)
  end

  # Parse a single Link header value (e.g., `<https://example.com/hub>; rel="hub"`)
  defp parse_link_header(link_header, rel) when is_binary(link_header) do
    Regex.scan(~r/<([^>]+)>;\s*rel="#{rel}"/, link_header)
    |> Enum.map(fn [_, link] -> link end)
    |> List.first()
  end

  defp parse_link_header(link_headers, rel) when is_list(link_headers) do
    Enum.find_value(link_headers, fn header -> parse_link_header(header, rel) end)
  end

  # Extract discovery links (hub or self) from the feed's body using Floki
  defp extract_link_from_body(body, rel) do
    body
    |> Floki.parse_document!()
    |> Floki.find(~s(link[rel="#{rel}"]))
    |> Enum.map(fn {_tag, attrs, _children} ->
      attrs |> Enum.into(%{}) |> Map.get("href")
    end)
    |> List.first()
  end

  def new(hub_url, callback_url, credentials \\ nil) do
    unless hub_url, do: raise(ArgumentError, "Please specify a hub url")
    unless callback_url, do: raise(ArgumentError, "Please specify a callback url")

    unless hub_url =~ ~r/^https?:\/\//i,
      do: raise(ArgumentError, "The specified hub url does not appear to be valid: #{hub_url}")

    %__MODULE__{
      hub_url: hub_url,
      callback_url: callback_url,
      credentials: credentials
    }
  end

  @doc """
  Subscribes to a topic URL through the hub.

  ## Parameters

  - `subscriber`: A PubSubHubbub.Subscriber struct
  - `topic_url`: The URL of the topic (feed) to subscribe to

  ## Examples

      iex> subscriber = new("http://hub.example.com", "http://callback.example.com")
      iex> # Assuming successful subscription
      iex> # {:ok, _} = subscribe(subscriber, "http://blog.example.com/feed")
      
      iex> subscriber = new("http://hub.example.com", "http://callback.example.com")
      iex> subscribe(subscriber, "not-a-url")
      ** (ArgumentError) The specified topic url does not appear to be valid: not-a-url
  """
  def subscribe(subscriber, topic_url) do
    change_subscription(subscriber, "subscribe", topic_url)
  end

  @doc """
  Unsubscribes from a topic URL through the hub.

  ## Parameters

  - `subscriber`: A PubSubHubbub.Subscriber struct
  - `topic_url`: The URL of the topic (feed) to unsubscribe from

  ## Examples

      iex> subscriber = new("http://hub.example.com", "http://callback.example.com")
      iex> # Assuming successful unsubscription
      iex> # {:ok, _} = unsubscribe(subscriber, "http://blog.example.com/feed")
      
      iex> subscriber = new("http://hub.example.com", "http://callback.example.com")
      iex> unsubscribe(subscriber, nil)
      ** (ArgumentError) Please specify a topic url
  """
  def unsubscribe(subscriber, topic_url) do
    change_subscription(subscriber, "unsubscribe", topic_url)
  end

  # Private functions

  @doc false
  defp change_subscription(subscriber, mode, topic_url) do
    unless topic_url, do: raise(ArgumentError, "Please specify a topic url")

    unless topic_url =~ ~r/^https?:\/\//i,
      do:
        raise(ArgumentError, "The specified topic url does not appear to be valid: #{topic_url}")

    post_params =
      %{
        "hub.mode" => mode,
        "hub.callback" => subscriber.callback_url,
        "hub.topic" => topic_url
      }
      |> maybe_add_param("hub.verify", subscriber.verify)
      |> maybe_add_param("hub.verify_token", subscriber.verify_token)
      |> maybe_add_param("hub.lease_seconds", subscriber.lease_seconds)

    headers =
      [
        {"User-Agent", "PubSubHubbub-Subscriber-Elixir/1.0"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
      |> maybe_add_auth(subscriber.credentials)

    opts =
      [headers: headers, form: post_params]
      |> Keyword.merge(Application.get_env(:bonfire_rss, :req_options, []))

    case Req.post(
           subscriber.hub_url,
           opts
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      e -> error(e)
    end
  end

  @doc false
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  @doc false
  defp maybe_add_auth(headers, nil), do: headers

  defp maybe_add_auth(headers, credentials) do
    [{"Authorization", "Basic " <> Base.encode64(credentials)} | headers]
  end
end
