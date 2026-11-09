require 'test_helper'

class TemplateDealableTest < ActiveSupport::TestCase
  test 'dealable_for excludes hidden Templates' do
    shown, hidden = seed_templates(2)
    hidden.update!(hidden_at: Time.current)
    room = room_with_players

    assert_equal [shown.id], Template.dealable_for(room).pluck(:id)
  end

  test 'unhiding makes a Template dealable again' do
    template, = seed_templates(1)
    template.update!(hidden_at: Time.current)
    room = room_with_players
    assert_empty Template.dealable_for(room)

    template.update!(hidden_at: nil)
    assert_equal [template.id], Template.dealable_for(room).pluck(:id)
  end

  test 'a hidden Template is never dealt' do
    seed_templates(Hand::SIZE)
    hidden = seed_templates(5)
    hidden.each { |template| template.update!(hidden_at: Time.current) }
    room = room_with_players

    room.start(by: room.host)

    room.games.last.rounds.first.hands.each do |hand|
      assert_empty hand.template_ids & hidden.map(&:id)
    end
  end

  test 'hiding a Template already in a live Hand leaves the Hand unchanged and captionable' do
    seed_templates(Hand::SIZE)
    room = room_with_players
    room.start(by: room.host)
    ada = room.host
    ids = room.hand_for(ada).template_ids.dup
    Template.find(ids.first).update!(hidden_at: Time.current)

    assert_equal ids, room.hand_for(ada).reload.template_ids
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture('drake.png')),
                                                  filename: 'm.png', content_type: 'image/png')
    meme = room.submit_meme(by: ada, signed_id: blob.signed_id, template_id: ids.first, captions: [])
    assert_equal ids.first, meme.template_id
  end
end
