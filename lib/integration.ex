defmodule Bonfire.RSS.Integration do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  use Bonfire.Common.E
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
  def process_and_save(parsed_feed, opts \\ [])

  def process_and_save(%{rss: feed}, opts) do
    channel_data =
      feed[:feed_info] ||
        Map.take(feed, [
          "webMaster",
          "managingEditor",
          "category",
          "generator",
          "description",
          "title",
          "link",
          "pubDate",
          "image",
          "language",
          "copyright"
        ])

    feed_info = prepare_feed_info(:rss, channel_data)

    (feed[:items] || feed["items"])
    |> Enum.map(&process_item(:rss, &1, feed_info, channel_data, opts))
  end

  def process_and_save(%{atom: feed}, opts) do
    channel_data =
      Map.take(feed, [
        "author",
        "category",
        "contributor",
        "generator",
        "subtitle",
        "title",
        "link",
        "updated",
        "icon",
        "logo",
        "rights"
      ])

    feed_info = prepare_feed_info(:atom, channel_data)

    feed["entries"]
    |> Enum.map(&process_item(:atom, &1, feed_info, channel_data, opts))
  end

  def process_and_save(%{items: _} = feed, opts) do
    process_and_save(%{rss: feed}, opts)
  end

  def process_and_save(%{"items" => _} = feed, opts) do
    process_and_save(%{rss: feed}, opts)
  end

  def process_and_save(%{"entries" => _} = feed, opts) do
    process_and_save(%{atom: feed}, opts)
  end

  def process_and_save(parsed_feed, opts) do
    error(parsed_feed, "Unrecognised feed type")
  end

  defp prepare_feed_info(:rss, %{"rss" => %{"channel" => %{} = channel}} = feed_info) do
    prepare_feed_info(:rss, feed_info |> Map.merge(channel) |> Map.drop(["rss"]))
  end

  defp prepare_feed_info(:rss, feed_info) do
    link = feed_info["link"]
    hostname = extract_hostname(link)
    title = feed_info["title"]
    description = feed_info["description"]

    # Construct bio
    bio = "Contributor to #{title} (#{description || "RSS feed"})"

    # Return a map with all the extracted variables
    Map.merge(feed_info, %{
      link: link,
      hostname: hostname,
      title: title,
      description: description,
      bio: bio
    })
  end

  defp prepare_feed_info(:atom, feed_info) do
    link = ed(feed_info, "links", "href", nil)
    hostname = extract_hostname(link)
    title = e(feed_info, "title", "value", nil)
    description = e(feed_info, "subtitle", nil)
    author = ed(feed_info, "contributor", "name", nil)
    username = String.downcase("#{hostname}_#{author || "contributor"}")

    # Construct bio
    bio = "Contributor to #{title} (#{description || "Atom feed"})"

    # Return a map with all the extracted variables
    Map.merge(feed_info, %{
      link: link,
      hostname: hostname,
      title: title,
      description: description,
      author: author,
      username: username,
      bio: bio
    })
  end

  defp prepare_item_info(:rss, feed_info, item) do
    item_link = item["link"]
    hostname = extract_hostname(feed_info[:link] || item_link)
    author = item["author"] || feed_info[:author]
    username = String.downcase("#{hostname}_#{author || "contributor"}")

    # Return a map with all the extracted variables
    Map.merge(feed_info, %{
      item_link: item_link,
      hostname: hostname,
      author: author,
      username: username
    })
  end

  defp prepare_item_info(:atom, feed_info, item) do
    item_link = ed(item, "links", "href", nil)
    hostname = extract_hostname(feed_info[:link] || item_link)
    author = ed(item, "authors", "name", nil) || feed_info[:author]
    username = String.downcase("#{hostname}_#{author || "contributor"}")

    # Return a map with all the extracted variables
    Map.merge(feed_info, %{
      item_link: item_link,
      hostname: hostname,
      author: author,
      username: username
    })
  end

  defp process_item(type, item, feed_info, channel_data, opts) do
    feed_info = prepare_item_info(type, feed_info, item)

    # Ensure user exists or create a new one
    user =
      Bonfire.Me.Users.get_or_create_service_user(
        feed_info[:username],
        %{
          name: feed_info[:author] || feed_info[:title],
          summary: feed_info[:bio],
          website: feed_info[:link],
          location: nil
        }
      )

    if feed_info[:item_link] do
      meta =
        Map.put(%{}, type, Map.put(item, :channel, channel_data))
        |> debug("meta")

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
            feed_info[:item_link],
            opts
          ),
        else:
          Bonfire.Files.Acts.URLPreviews.maybe_save(
            user,
            feed_info[:item_link],
            meta,
            opts
          )
    else
      debug(item, "no link")
    end
  end

  defp extract_hostname(url) do
    # Extract the hostname from the feed URL
    case is_binary(url) and URI.parse(url) do
      %URI{host: host} -> host
      _ -> nil
    end
  end
end
