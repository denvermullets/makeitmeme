ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module ActiveSupport
  class TestCase
    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    ADMIN_PASSWORD = 'correct-horse'.freeze

    # Run the block with the Admin password env var set (nil unsets it).
    def with_admin_password(value = ADMIN_PASSWORD)
      original = ENV.fetch('ADMIN_PASSWORD', nil)
      value.nil? ? ENV.delete('ADMIN_PASSWORD') : ENV['ADMIN_PASSWORD'] = value
      yield
    ensure
      original.nil? ? ENV.delete('ADMIN_PASSWORD') : ENV['ADMIN_PASSWORD'] = original
    end

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

    # Start an Upload draft through the Upload operation from a test fixture image (`file: nil` sends no file).
    def start_upload_draft(token: 'tok', nickname: 'Pat', file: 'drake.png', room_code: nil)
      upload = file && Rack::Test::UploadedFile.new(file_fixture(file), file.end_with?('.jpg') ? 'image/jpeg' : 'image/png')
      Upload.start(file: upload, browser_token: token, nickname:, room_code:)
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

module ActionDispatch
  class IntegrationTest
    # Sign this integration session in as the Admin through the real sign-in form.
    def sign_in_as_admin(password = ActiveSupport::TestCase::ADMIN_PASSWORD)
      with_admin_password(password) { post admin_sign_in_path, params: { password: password } }
    end
  end
end
