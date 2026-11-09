module MemeHelper
  # Download file name for a saved Meme, e.g. "round-2-ada.png". The nickname is reduced to a filename-safe slug
  # (a nickname with nothing safe in it, such as emoji only, becomes "player").
  def meme_download_name(round, meme)
    nickname = meme.game_player.nickname.to_s.parameterize.presence || 'player'
    "round-#{round.number}-#{nickname}.png"
  end
end
