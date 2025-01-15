defmodule Bonfire.RSS.Integration do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  import Untangle

  def repo, do: Config.repo()

  @doc """
  Processes a parsed RSS feed and saves it to the database.

  Creates a user per author if none exists and publishes each RSS item as a post.

  ## Parameters
  - `parsed_feed`: The parsed feed structure.

  ## Returns
  - A list of results for each processed item.
  """
  def process_and_save(parsed_feed, opts \\ []) do
    parsed_feed.items
    |> Enum.map(&process_item(&1, parsed_feed[:feed_info] || %{}, opts))
  end

  defp process_item(item, feed_info, opts) do
    # Extract or default the author
    item_link = item["link"]
    channel_url = feed_info["rss"]["channel"]["link"] || item_link
    hostname = extract_hostname(channel_url)
    channel_title = feed_info["rss"]["channel"]["title"]
    channel_description = feed_info["rss"]["channel"]["description"]
    author_name = item["author"]
    username = String.downcase("#{hostname}_#{item["author"] || "contributor"}")

    # Extract author bio from feed or use a default bio
    bio = "Contributor to #{channel_title} (#{channel_description || "RSS feed"})"

    # Ensure user exists or create a new one
    user =
      Bonfire.Me.Fake.fake_user!(
        username,
        %{name: author_name || channel_title, summary: bio, website: channel_url, location: nil},
        request_before_follow: false,
        undiscoverable: false,
        skip_spam_check: true
      )

    if item_link do
      meta = %{rss: Map.merge(feed_info["rss"] || %{}, item)}

      opts =
        opts
        # to upsert metadata:
        |> Keyword.put_new(:update_existing, true)
        # or to (re)publish the activity:
        |> Keyword.put_new(:update_existing, :force)
        |> Keyword.merge(
          id: Bonfire.Common.DatesTimes.maybe_generate_ulid(item["pubDate"]),
          post_create_fn: fn current_user, media, opts ->
            Bonfire.Social.Objects.publish(
              current_user,
              :create,
              media,
              [boundary: "local"],
              __MODULE__
            )
          end,
          extra: meta
        )

      # TODO: optionally use this instead to not re-fetch each iterm: Bonfire.Files.Acts.URLPreviews.maybe_save(
      if opts[:fetch_items],
        do:
          Bonfire.Files.Acts.URLPreviews.maybe_fetch_and_save(
            user,
            item_link,
            opts
          ),
        else:
          Bonfire.Files.Acts.URLPreviews.maybe_save(
            user,
            item_link,
            meta,
            opts
          )
    end
  end

  defp extract_hostname(url) do
    # Extract the hostname from the feed URL
    case URI.parse(url) do
      %URI{host: host} -> host
      _ -> nil
    end
  end
end
