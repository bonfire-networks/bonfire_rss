import Config

#   Configure Req.Test stub 
config :bonfire_rss, :req_options, plug: {Req.Test, Bonfire.RSS}
