require 'test_helper'

# MEME-93: a Meme keeps its baked image, maker and points after the Admin hard-deletes its Template, and the
# Scoreboard, Memes tab and Recap never read a Meme's Template to render it.
class MemesOutliveTemplateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Raises if anything reads a Meme's Template association while active.
  module TemplateReadGuard
    mattr_accessor :active, default: false

    def template
      raise 'a Meme\'s Template was read' if TemplateReadGuard.active

      super
    end
  end
  Meme.prepend(TemplateReadGuard)

  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
    @host.post start_room_path(@room.code)
    @game = @room.reload.current_game
    @round = @game.rounds.order(:number).first
    @template = Template.first
    @meme = make_meme('Bob', @template)
  end

  teardown { TemplateReadGuard.active = false }

  def make_meme(nickname, template)
    seat = @game.game_players.find_by!(nickname:)
    Meme.create!(round: @round, game_player: seat, template:, position: 0, points: 4, caption_texts: []).tap do |meme|
      meme.image.attach(io: File.open(file_fixture('drake.png')), filename: 'drake.png', content_type: 'image/png')
    end
  end

  def admin_hard_delete(template)
    sign_in_as_admin
    perform_enqueued_jobs { delete admin_template_path(template) }
    assert_not Template.exists?(template.id)
  end

  def advance_to_scoreboard
    20.times do
      break if @room.reload.scoreboard?

      travel_to(@room.phase_deadline_at + 1.second) { @room.advance! }
    end
    assert_predicate @room, :scoreboard?
    @meme.update_columns(points: 4) # scoring recomputes the cached points from Votes
  end

  def finish_game
    advance_to_scoreboard
    @game.reload
  end

  def assert_meme_rendered(session = self)
    session.assert_select '#memes_by_round li[data-nickname="Bob"] img[src*="/rails/active_storage/"]'
    session.assert_select '#memes_by_round li[data-nickname="Bob"] [data-meme-points]', text: '4'
  end

  test 'Admin hard delete nulls the Meme Template link and keeps its image' do
    admin_hard_delete(@template)

    assert_nil @meme.reload.template_id
    assert @meme.image.attached?
    assert ActiveStorage::Blob.exists?(@meme.image.blob.id)
  end

  test 'mid-Game, after the Admin hard-deletes the Template, the Memes tab still renders the Meme' do
    advance_to_scoreboard
    admin_hard_delete(@template)

    TemplateReadGuard.active = true
    @bob.get room_path(@room.code)

    @bob.assert_response :success
    assert_meme_rendered(@bob)
  end

  test 'after the Admin hard-deletes the Template, the Recap still renders the Meme with image, maker and points' do
    finish_game
    admin_hard_delete(@template)

    TemplateReadGuard.active = true
    get recap_path(@game.recap_token)

    assert_response :success
    assert_meme_rendered
  end

  test 'rendering the Recap never queries Templates, even with the Template intact' do
    finish_game
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM "templates"/ }

    TemplateReadGuard.active = true
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get recap_path(@game.recap_token)
    end

    assert_empty queries
    assert_meme_rendered
  end
end
