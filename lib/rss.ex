defmodule Bonfire.RSS do
  use Arrows
  use Untangle
  import Reed.Transformers
  alias Bonfire.RSS.Integration

  def import(feed_url, opts \\ []) do
    get(feed_url, opts)
    ~> Integration.process_and_save(opts)
  end

  def get(feed_url, opts \\ []) do
    opts =
      (opts ++ [headers: [{"Accept", "application/rss+xml, application/xml"}]])
      |> Keyword.merge(Application.get_env(:bonfire_rss, :req_options, []))

    {:ok, response} =
      Req.get(feed_url, opts)

    case response do
      %Req.Response{status: 200, body: body, headers: headers} ->
        parse(body)
        |> debug("Parsed feed")

      %Req.Response{status: status} ->
        {:error, "Failed to fetch feed. Status: #{status}"}
    end
  end

  def parse(body, _opts \\ []) do
    case detect_feed_type(body) do
      :rss ->
        with {:ok, parsed} <- FastRSS.parse_rss(body) do
          {:ok, %{rss: parsed}}
        end

      :atom ->
        with {:ok, parsed} <- FastRSS.parse_atom(body) do
          {:ok, %{atom: parsed}}
        end

      _ ->
        error("Unknown feed type")
    end
  end

  def detect_feed_type(feed_string) do
    cond do
      # TODO: optimise detection
      feed_string |> String.contains?("<rss") ->
        :rss

      feed_string |> String.contains?("<feed") ->
        :atom

      true ->
        :unknown
    end
  end

  # def get(rss_url, opts \\ []) do
  #   with {:ok, req} <- Reed.get(rss_url, transform: transform_opts(opts)) do
  #     {:ok, Req.Response.get_private(req, :rss)}
  #   end
  # end

  # def transform_opts(opts) do
  #   fn state ->
  #     state
  #     |> collect()
  #     |> limit(opts[:limit] || 50)
  #     |> transform()
  #   end
  # end

  # @doc """
  # Parses an RSS feed string and transforms its items using the provided `Reed`s pipeline.

  # ## Options
  # - `:transform` - An arity-1 function or a list of arity-1 functions to process each RSS item.

  # ## Examples

  #     iex> content = "<rss><channel><item><title>Example</title></item></channel></rss>"
  #     iex> transform = fn item -> Map.put(item, :custom, true) end
  #     iex> Reed.RSSParser.parse(content, transform: transform)
  #     [%{title: "Example", custom: true}]
  # """
  # def parse(rss_content, opts \\ []) do
  #   transform = Keyword.get(opts, :transform) || transform_opts(opts)

  #   item_handler =
  #     cond do
  #       is_function(transform, 1) ->
  #         [transform]

  #       is_list(transform) && Enum.all?(transform, &is_function/1) ->
  #         transform

  #       true ->
  #         raise ArgumentError,
  #               "`:transform` must either be an arity-1 function or a list of arity-1 functions"
  #     end

  #   {:ok, partial} = Saxy.Partial.new(Reed.Handler, %Reed.State{transform: item_handler})

  #   case parse_rss_content(partial, rss_content) do
  #     {:ok, final_state} ->
  #       return_rss_map(final_state)

  #     other ->
  #       other
  #   end
  # end

  # defp parse_rss_content(partial, content) do
  #   case Saxy.Partial.parse(partial, content) do
  #     {:cont, new_partial} ->
  #       {:ok, Saxy.Partial.get_state(new_partial)}

  #     {:halt, final_user_state} ->
  #       {:ok, final_user_state}

  #     other ->
  #       other
  #   end
  # end

  # defp return_rss_map(final_state) do
  #   case Reed.Handler.client_state(final_state) do
  #     %{private: %{items: _} = private} = map ->
  #       {:ok, Map.merge(map, private) |> Map.drop([:private])}

  #     %{} = map ->
  #       {:ok, map}

  #     other ->
  #       error(other)
  #   end
  # end
end
