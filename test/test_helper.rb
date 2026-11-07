ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Fill the Template Library with `count` Templates, each with an attached image.
    def seed_templates(count = Hand::SIZE)
      Array.new(count) do |i|
        Template.create!(memegen_id: "t#{i}-#{SecureRandom.hex(3)}", name: "Template #{i}",
                         text_boxes: []).tap do |template|
          template.image.attach(io: File.open(file_fixture('drake.png')), filename: 'drake.png',
                                content_type: 'image/png')
        end
      end
    end

    # A Room whose Host (Ada) is joined by Bob and Cy.
    def room_with_players
      room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada')
      Room.join(code: room.code, nickname: 'Bob', browser_token: 'bob')
      Room.join(code: room.code, nickname: 'Cy', browser_token: 'cy')
      room
    end

    # Each named Player (browser token) submits a Meme from their first dealt Template this Round.
    def submit_memes(room, *tokens)
      tokens.map do |token|
        player = room.player_for(token)
        blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture('drake.png')),
                                                      filename: 'drake.png', content_type: 'image/png')
        room.submit_meme(by: player, signed_id: blob.signed_id,
                         template_id: room.hand_for(player).template_ids.first, captions: [])
      end
    end
  end
end
