# A restart drops every cable connection without running unsubscribe, so presence is reset before the server accepts
# its first connection (a client reconnecting earlier would otherwise be zeroed and shown Away while connected).
# Only in the server process (`rails server`), never console, rake, assets:precompile or tests. A failure here must
# never stop the app from serving. Single box only: with several, one box's boot would reset the connections of the
# others.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server)

  begin
    Player.reset_presence!
  rescue StandardError => e
    Rails.logger.error("Presence reset on boot failed: #{e.class}: #{e.message}")
  end
end
