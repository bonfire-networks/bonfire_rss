defmodule Bonfire.RSS.PubSubHubbub.SubscriberTest do
  use ExUnit.Case, async: true
  alias Bonfire.RSS.PubSubHubbub

  doctest PubSubHubbub, import: true

  # Define test constants that match the original PHP example
  @hub_host "hub.example.com"
  @hub_url "http://#{@hub_host}"
  @callback_url "http://example.com/callback"
  @feed "http://feeds.feedburner.com/onlineaspect"

  describe "new/3" do
    test "creates a new subscriber with valid parameters" do
      subscriber = PubSubHubbub.new(@hub_url, @callback_url)

      assert subscriber.hub_url == @hub_url
      assert subscriber.callback_url == @callback_url
      assert subscriber.credentials == nil
      assert subscriber.verify == "async"
    end

    test "creates a new subscriber with credentials" do
      credentials = "username:password"
      subscriber = PubSubHubbub.new(@hub_url, @callback_url, credentials)

      assert subscriber.credentials == credentials
    end

    test "raises error with invalid hub URL" do
      assert_raise ArgumentError, ~r/hub url does not appear to be valid/, fn ->
        PubSubHubbub.new("invalid-url", @callback_url)
      end
    end

    test "raises error with missing hub URL" do
      assert_raise ArgumentError, "Please specify a hub url", fn ->
        PubSubHubbub.new(nil, @callback_url)
      end
    end

    test "raises error with missing callback URL" do
      assert_raise ArgumentError, "Please specify a callback url", fn ->
        PubSubHubbub.new(@hub_url, nil)
      end
    end
  end

  describe "subscribe/2" do
    setup do
      subscriber = PubSubHubbub.new(@hub_url, @callback_url)
      %{subscriber: subscriber}
    end

    test "successfully subscribes to a feed", %{subscriber: subscriber} do
      Req.Test.stub(Bonfire.RSS, fn conn ->
        assert conn.method == "POST"
        assert conn.host == @hub_host

        params = plug_body(conn)
        assert params["hub.mode"] == "subscribe"
        assert params["hub.callback"] == @callback_url
        assert params["hub.topic"] == @feed
        assert params["hub.verify"] == "async"

        # , status: 202)
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = PubSubHubbub.subscribe(subscriber, @feed)
    end

    test "handles subscription failure", %{subscriber: subscriber} do
      Req.Test.stub(Bonfire.RSS, fn conn ->
        Req.Test.json(conn, %{error: "Bad Request"}, status: 400)
      end)

      Req.Test.expect(Bonfire.RSS, 2, &Plug.Conn.send_resp(&1, 400, "Bad Request"))

      assert :error = PubSubHubbub.subscribe(subscriber, @feed)
    end

    test "handles network error", %{subscriber: subscriber} do
      Req.Test.stub(Bonfire.RSS, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _} = PubSubHubbub.subscribe(subscriber, @feed)
    end

    test "raises error with invalid feed URL", %{subscriber: subscriber} do
      assert_raise ArgumentError, ~r/topic url does not appear to be valid/, fn ->
        PubSubHubbub.subscribe(subscriber, "invalid-url")
      end
    end
  end

  describe "unsubscribe/2" do
    setup do
      subscriber = PubSubHubbub.new(@hub_url, @callback_url)
      %{subscriber: subscriber}
    end

    test "successfully unsubscribes from a feed", %{subscriber: subscriber} do
      Req.Test.stub(Bonfire.RSS, fn conn ->
        assert conn.method == "POST"
        assert conn.host == @hub_host

        params = plug_body(conn)
        assert params["hub.mode"] == "unsubscribe"
        assert params["hub.callback"] == @callback_url
        assert params["hub.topic"] == @feed
        assert params["hub.verify"] == "async"

        # , status: 202)
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = PubSubHubbub.unsubscribe(subscriber, @feed)
    end

    test "handles unsubscription failure", %{subscriber: subscriber} do
      Req.Test.stub(Bonfire.RSS, fn conn ->
        Req.Test.json(conn, %{error: "Bad Request"})
      end)

      Req.Test.expect(Bonfire.RSS, 2, &Plug.Conn.send_resp(&1, 400, "Bad Request"))

      assert {:error, _} = PubSubHubbub.unsubscribe(subscriber, @feed)
    end

    test "raises error with invalid feed URL", %{subscriber: subscriber} do
      assert_raise ArgumentError, ~r/topic url does not appear to be valid/, fn ->
        PubSubHubbub.unsubscribe(subscriber, "invalid-url")
      end
    end
  end

  def plug_body(conn, opts \\ []) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    URI.decode_query(body)
  end
end
