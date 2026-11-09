require 'test_helper'

class TemplateLibraryTest < ActiveSupport::TestCase
  MANIFEST = Rails.root.join('test/fixtures/files/templates_manifest.json')

  setup do
    @downloads = []
    @fetcher = lambda do |url|
      @downloads << url
      File.binread(Rails.root.join('test/fixtures/files', url.include?('3hd') ? 'three_heads.png' : 'drake.png'))
    end
  end

  test 'importing the manifest fills the Template Library, each with an image' do
    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)

    assert_equal 2, Template.count
    assert(Template.all.all? { |t| t.image.attached? })
  end

  test 'a two-box Template has its Text Boxes as top and bottom fractions' do
    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)

    drake = Template.find_by!(memegen_id: 'drake')
    assert_equal 'Drake Hotline Bling', drake.name
    assert_equal 'https://knowyourmeme.com/memes/drakeposting', drake.source
    assert_equal [
      { 'x' => 0.0, 'y' => 0.0, 'w' => 1.0, 'h' => 0.2, 'angle' => 0, 'color' => 'white', 'font' => 'thin' },
      { 'x' => 0.0, 'y' => 0.8, 'w' => 1.0, 'h' => 0.2, 'angle' => 0, 'color' => 'white', 'font' => 'thin' }
    ], drake.text_boxes
  end

  test 'imports are marked memegen and left unreviewed and visible' do
    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)

    assert(Template.all.all? { |t| t.source_kind == 'memegen' && t.reviewed_at.nil? && t.hidden_at.nil? })
  end

  test 're-importing adds no duplicates and downloads nothing more' do
    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)
    downloads_after_first = @downloads.size

    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)

    assert_equal 2, Template.count
    assert_equal 2, ActiveStorage::Blob.count
    assert_equal downloads_after_first, @downloads.size
  end

  test 're-importing updates changed names and Text Boxes' do
    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)
    Template.find_by!(memegen_id: 'drake').update!(name: 'Old', text_boxes: [])

    TemplateLibrary.import(MANIFEST, fetcher: @fetcher)

    drake = Template.find_by!(memegen_id: 'drake')
    assert_equal 'Drake Hotline Bling', drake.name
    assert_equal 2, drake.text_boxes.size
  end
end

class TemplateImageServingTest < ActionDispatch::IntegrationTest
  test 'a Template image is served same-origin through the Active Storage proxy route' do
    TemplateLibrary.import(TemplateLibraryTest::MANIFEST,
                           fetcher: ->(_url) { File.binread(Rails.root.join('test/fixtures/files/drake.png')) })
    template = Template.find_by!(memegen_id: 'drake')

    get rails_storage_proxy_path(template.image)

    assert_response :success
    assert_equal 'image/png', response.media_type
  end
end
