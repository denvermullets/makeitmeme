require 'test_helper'

class ImgflipImportTest < ActiveSupport::TestCase
  MEMES = [
    { 'id' => '181913649', 'name' => 'Drake Hotline Bling', 'url' => 'https://i.imgflip.com/30b1gx.jpg',
      'box_count' => 2 },
    { 'id' => '112126428', 'name' => 'Distracted Boyfriend', 'url' => 'https://i.imgflip.com/1ur9b0.jpg', 'box_count' => 3 }
  ].freeze

  setup do
    @memes = MEMES.map(&:dup)
    @downloads = []
    @failing = []
    @fetcher = lambda do |url|
      next { 'success' => true, 'data' => { 'memes' => @memes } }.to_json if url == ImgflipImport::API_URL
      raise "Download failed (404): #{url}" if @failing.include?(url)

      @downloads << url
      File.binread(file_fixture('drake.png'))
    end
  end

  test 'imports each meme into the Imgflip Pack, unreviewed, with an image' do
    result = ImgflipImport.import(fetcher: @fetcher)

    assert_equal 2, result.added
    drake = Template.find_by!(memegen_id: 'imgflip-181913649')
    assert_equal 'Drake Hotline Bling', drake.name
    assert_equal 'imgflip', drake.source_kind
    assert_equal 'Imgflip', drake.pack.name
    assert drake.needs_review?
    assert drake.image.attached?
  end

  test 'two boxes are top and bottom; more are full-width strips stacked top to bottom' do
    ImgflipImport.import(fetcher: @fetcher)

    assert_equal TextBoxes::TOP_AND_BOTTOM, Template.find_by!(memegen_id: 'imgflip-181913649').text_boxes
    boxes = Template.find_by!(memegen_id: 'imgflip-112126428').text_boxes
    assert_equal [0.0, 0.4, 0.8], boxes.pluck('y')
    assert_equal([[1.0, 0.2]] * 3, boxes.map { |box| [box['w'], box['h']] })
    assert TextBoxes.check(ImgflipImport.strips(5)).valid?
  end

  test 're-importing adds nothing and downloads nothing more' do
    ImgflipImport.import(fetcher: @fetcher)
    downloads = @downloads.size

    result = ImgflipImport.import(fetcher: @fetcher)

    assert_equal [0, 2], [result.added, result.skipped]
    assert_equal downloads, @downloads.size
    assert_equal 2, Template.where(source_kind: 'imgflip').count
  end

  test 'a deleted import does not come back' do
    ImgflipImport.import(fetcher: @fetcher)
    Template.find_by!(memegen_id: 'imgflip-181913649').destroy

    ImgflipImport.import(fetcher: @fetcher)

    assert_not Template.exists?(memegen_id: 'imgflip-181913649')
  end

  test 'a meme named like an existing Template is skipped, ignoring case and punctuation' do
    Template.create!(memegen_id: 'db', name: 'distracted boyfriend!', text_boxes: [])

    result = ImgflipImport.import(fetcher: @fetcher)

    assert_equal [1, 1], [result.added, result.skipped]
    assert_not Template.exists?(memegen_id: 'imgflip-112126428')
  end

  test 'a failed download creates nothing for that meme and is retried next run' do
    @failing << 'https://i.imgflip.com/1ur9b0.jpg'

    result = ImgflipImport.import(fetcher: @fetcher)

    assert_equal [1, 1], [result.added, result.failed]
    assert_not Template.exists?(memegen_id: 'imgflip-112126428')

    @failing.clear
    assert_equal 1, ImgflipImport.import(fetcher: @fetcher).added
  end

  test 'an API error raises' do
    fetcher = ->(_url) { { 'success' => false, 'error_message' => 'nope' }.to_json }

    assert_raises(RuntimeError, match: /nope/) { ImgflipImport.import(fetcher: fetcher) }
  end
end
