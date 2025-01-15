defmodule Bonfire.RSS do
  use Untangle
  import Reed.Transformers

  def get(rss_url, opts) do
    Reed.get(rss_url, transform: transform_opts(opts))
  end

  def transform_opts(opts) do
    fn state ->
      state
      |> collect()
      |> limit(opts[:limit] || 50)
      |> transform()
    end
  end

  @doc """
  Parses an RSS feed string and transforms its items using the provided `Reed`s pipeline.

  ## Options
  - `:transform` - An arity-1 function or a list of arity-1 functions to process each RSS item.

  ## Examples

      iex> content = "<rss><channel><item><title>Example</title></item></channel></rss>"
      iex> transform = fn item -> Map.put(item, :custom, true) end
      iex> Reed.RSSParser.parse(content, transform: transform)
      [%{title: "Example", custom: true}]
  """
  def parse(rss_content, opts \\ []) do
    transform = Keyword.get(opts, :transform) || transform_opts(opts)

    item_handler =
      cond do
        is_function(transform, 1) ->
          [transform]

        is_list(transform) && Enum.all?(transform, &is_function/1) ->
          transform

        true ->
          raise ArgumentError,
                "`:transform` must either be an arity-1 function or a list of arity-1 functions"
      end

    {:ok, partial} = Saxy.Partial.new(Reed.Handler, %Reed.State{transform: item_handler})

    case parse_rss_content(partial, rss_content) do
      {:ok, final_state} ->
        return_rss_map(final_state)

      other ->
        other
    end
  end

  defp parse_rss_content(partial, content) do
    case Saxy.Partial.parse(partial, content) do
      {:cont, new_partial} ->
        {:ok, Saxy.Partial.get_state(new_partial)}

      {:halt, final_user_state} ->
        {:ok, final_user_state}

      other ->
        other
    end
  end

  defp return_rss_map(final_state) do
    case Reed.Handler.client_state(final_state) do
      %{private: %{items: _} = private} = map ->
        {:ok, Map.merge(map, private) |> Map.drop([:private])}

      %{} = map ->
        {:ok, map}

      other ->
        error(other)
    end
  end
end
