defmodule Bonfire.RSS.Web.AboutLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_nav_link(l("About"),
    page: "About",
    href: "/bonfire_rss/about",
    icon: "typcn:info-large"
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page: "About",
       page_title: "About the extension",
       nav_items: Bonfire.Common.ExtensionModule.default_nav(:bonfire_rss)
     )}
  end

  def handle_event(
        "custom_event",
        _attrs,
        socket
      ) do
    # handle the event here
    {:noreply, socket}
  end
end
