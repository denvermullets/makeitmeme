require 'application_system_test_case'

# One whole Game on three phones (three browser sessions), through the real pages and the real Meme editor:
# create, join, start, caption and submit, vote, Scoreboard totals, Play again back to Waiting.
#
# Run with `bin/rails test:system` (needs Chrome). Not part of `bin/rails test` or CI.
#
# Scoring is deterministic: every Player submits a Meme every Round and everyone votes Up on every Meme but their
# own, so each Meme earns +2 and each Player ends the 3 Rounds on 6, tied for first place.
#
# The separate each_player loops are deliberate: every phone must reach a state before any phone moves on.
class FullGameTest < ApplicationSystemTestCase
  PLAYERS = %w[Ada Bob Cy].freeze
  BOX = { 'x' => 0.1, 'y' => 0.2, 'w' => 0.5, 'h' => 0.25, 'angle' => 0, 'color' => 'white', 'font' => 'thick' }.freeze

  setup do
    @original_phase_seconds = Room.phase_seconds
    # Captioning must outlast the three sequential submits, vote the three clicks, and the reveal the three
    # sessions checking it in turn.
    Room.phase_seconds = { captioning: 20, vote: 6, reveal: 4 }
    seed_templates(Hand::SIZE + 2).each { |template| template.update!(text_boxes: [BOX]) }
  end

  teardown do
    Room.phase_seconds = @original_phase_seconds
  end

  test 'three Players play a whole Game and play again' do
    using_wait_time(20) do
      create_and_join_room
      start_game

      Room::ROUNDS_PER_GAME.times do |index|
        round = index + 1
        each_player { assert_selector "#captioning[data-round='#{round}']" }
        each_player { caption_and_submit("Round #{round} from #{@current_name}") }
        PLAYERS.size.times { vote_up_on_current_meme }
      end

      each_player { assert_selector '#scoreboard' }
      each_player do
        PLAYERS.each { |name| assert_selector '#scoreboard li', text: "1 #{name} #{Room::ROUNDS_PER_GAME * 2}" }
      end

      play_again
    end
  end

  private

  # Runs the block once per Player, in that Player's own browser session (own cookies, own cable connection).
  def each_player
    PLAYERS.each do |name|
      using_session(name) do
        @current_name = name
        yield name
      end
    end
  end

  def create_and_join_room
    using_session('Ada') do
      visit root_path
      find('#nickname').set('Ada')
      click_button 'Create a Room'
      assert_selector '[data-room-code]'
      @code = find('[data-room-code]').text
    end

    (PLAYERS - ['Ada']).each { |name| using_session(name) { join_room(name) } }

    # Everyone sees everyone, arrived over the Room stream.
    each_player { PLAYERS.each { |name| assert_selector '#players li', text: name } }
  end

  def join_room(name)
    visit root_path
    find('#code').set(@code)
    find('#join_nickname').set(name)
    click_button 'Join'
    assert_selector '[data-room-code]', text: @code
  end

  def start_game
    using_session('Ada') { click_button 'Start' }
  end

  # The editor loads the Hand's images and font first; its body appears when ready. One Text Box per Template.
  def caption_and_submit(text)
    assert_selector '.meme-editor-body'
    fill_in 'Caption for box 1', with: text
    click_button 'Submit Meme'
    assert_selector '.meme-submitted', text: 'Meme submitted', visible: :visible
  end

  # Every Player but the maker taps Up on the Meme under vote; then everyone sees the reveal with its points.
  def vote_up_on_current_meme
    each_player do
      assert_selector '#vote'
      # Either the three buttons or "This one's yours." arrives on the Player's private stream.
      assert_selector '#vote_controls button, #vote_controls p'
      click_button 'Up' if has_button?('Up', wait: 0)
    end
    each_player do
      assert_selector '#reveal'
      assert_selector '#reveal_points', text: '+2'
    end
  end

  def play_again
    using_session('Ada') { click_button 'Play again' }
    each_player { assert_selector '#waiting' }
    PLAYERS.each { |name| using_session('Bob') { assert_selector '#players li', text: name } }
    using_session('Ada') { assert_button 'Start' }
  end
end
