require 'test_helper'

# Room game operation: a Player submits their baked Meme during Captioning.
class RoomSubmitMemeTest < ActiveSupport::TestCase
  BOX = { 'x' => 0.1, 'y' => 0.2, 'w' => 0.5, 'h' => 0.25, 'angle' => 0, 'color' => 'white', 'font' => 'thick' }.freeze

  setup do
    @room = room_with_players
    seed_templates(30).each { |template| template.update!(text_boxes: [BOX, BOX]) }
    @room.start(by: @room.player_for('ada'))
    @bob = @room.player_for('bob')
  end

  def blob(fixture: 'drake.png', content_type: 'image/png')
    ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture(fixture)), filename: fixture,
                                           content_type:)
  end

  def submit(player: @bob, signed_id: blob.signed_id, template_id: @room.hand_for(player).template_ids.first,
             captions: %w[top bottom])
    @room.submit_meme(by: player, signed_id:, template_id:, captions:)
  end

  def rejected_with(message, &)
    error = assert_raises(ActiveRecord::RecordInvalid, &)
    assert_includes error.record.errors.full_messages, message
  end

  test 'a Player submits their baked PNG with the Template and caption texts' do
    template_id = @room.hand_for(@bob).template_ids.third
    meme = submit(template_id:, captions: ['  top  ', 'bottom'])

    assert meme.image.attached?
    assert_equal 'image/png', meme.image.content_type
    assert_equal template_id, meme.template_id
    assert_equal %w[top bottom], meme.caption_texts
    assert_equal @bob.id, meme.game_player.player_id
    assert_equal @room.current_game.rounds.find_by(number: 1), meme.round
    assert_equal [0, 0, 0, 0], [meme.points, meme.up_count, meme.meh_count, meme.down_count]
    assert_nil meme.position
    assert_equal meme, @room.hand_for(@bob).meme
  end

  test 'blank captions are fine and extra or missing ones are fitted to the Template' do
    meme = submit(captions: ['', 'x' * 200, 'extra'])

    assert_equal ['', 'x' * Meme::CAPTION_MAX], meme.caption_texts
    assert_equal ['', ''], submit(player: @room.player_for('cy'), captions: nil).caption_texts
  end

  test 'rejects outside Captioning' do
    @room.update!(phase: :scoreboard)
    rejected_with('Memes can only be submitted during Captioning') { submit }
  end

  test 'rejects a Template that is not in the Players Hand' do
    other = Template.where.not(id: @room.hand_for(@bob).template_ids).first
    rejected_with('That Template is not in your Hand') { submit(template_id: other.id) }
  end

  test 'rejects a second submission' do
    submit
    rejected_with('You already submitted a Meme this Round') { submit }
    assert_equal 1, Meme.count
  end

  test 'rejects a file that is not a PNG, by claimed type or by content' do
    json = ->(type) { blob(fixture: 'templates_manifest.json', content_type: type).signed_id }
    rejected_with('The Meme must be a PNG') { submit(signed_id: json.call('application/json')) }
    rejected_with('The Meme must be a PNG') { submit(signed_id: json.call('image/png')) }
    rejected_with('The Meme must be a PNG') { submit(signed_id: 'garbage') }
  end

  test 'rejects an oversized file' do
    bytes = Meme::PNG_SIGNATURE + ('0' * Meme::MAX_BYTES)
    big = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'big.png',
                                                 content_type: 'image/png')
    rejected_with("The Meme is too big (max #{Meme::MAX_BYTES / 1.megabyte} MB)") { submit(signed_id: big.signed_id) }
  end

  test 'rejects a Player who is not in this Game' do
    stranger = Player.create!(room: Room.create_with_host(nickname: 'Zed', browser_token: 'zed'),
                              nickname: 'Y', browser_token: 'y', joined_at: Time.current)
    rejected_with('You are not in this Game') { submit(player: stranger, template_id: 1) }
  end

  test 'a submission just after the deadline is taken within the grace, and rejected beyond it' do
    deadline = @room.reload.phase_deadline_at
    travel_to(deadline + 0.5.seconds) { assert submit }

    travel_to(deadline + Room::SUBMISSION_GRACE + 1.second) do
      rejected_with('Time is up') { submit(player: @room.player_for('cy')) }
    end
  end

  test 'the deadline waits out the grace, so a Meme arriving at zero still counts' do
    deadline = @room.reload.phase_deadline_at
    travel_to(deadline + 0.1.seconds) do
      assert_not @room.advance!(from_seq: @room.phase_seq, only_if_due: true)
      assert @room.reload.captioning?
    end
    travel_to(deadline + Room::SUBMISSION_GRACE + 1.second) do
      assert @room.advance!(from_seq: @room.phase_seq, only_if_due: true)
      assert_equal 2, @room.reload.current_round_number
    end
  end
end
