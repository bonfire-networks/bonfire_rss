defmodule Bonfire.RSS.Web.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/bonfire_rss/" do
        pipe_through(:browser)

        live("/", Bonfire.RSS.Web.HomeLive)
        live("/about", Bonfire.RSS.Web.AboutLive)
      end

      scope "/bonfire_rss/" do
        pipe_through(:basic_json)

        get "/webhook", Bonfire.RSS.PubSubHubbub.WebhookController, :callback
        post "/webhook", Bonfire.RSS.PubSubHubbub.WebhookController, :posted
      end

      # pages only guests can view
      scope "/bonfire_rss/", Bonfire.RSS.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      # pages you need an account to view
      scope "/bonfire_rss/", Bonfire.RSS.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/bonfire_rss/", Bonfire.RSS.Web do
        pipe_through(:browser)
        pipe_through(:user_required)
      end

      # pages only admins can view
      scope "/bonfire_rss/admin", Bonfire.RSS.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)
      end
    end
  end
end
