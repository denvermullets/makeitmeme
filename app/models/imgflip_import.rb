require 'net/http'

# Adds Imgflip's current top memes (GET https://api.imgflip.com/get_memes, about 100) to the Template Library.
# Imgflip gives only a box count, so Text Boxes are guessed as full-width strips and every import lands
# unreviewed in the Imgflip Pack for the Admin to fix or hide.
#
# Insert-only and safe to re-run:
# - keyed by "imgflip-<id>" in memegen_id, so a Template already imported is skipped and never updated
# - a deleted import is tombstoned (Template#after_destroy) and never comes back
# - a meme whose name matches an existing Template (any source, ignoring case and punctuation) is skipped
# - a Template is created only once its image has downloaded; a failed download is skipped and retried next run
module ImgflipImport
  API_URL = 'https://api.imgflip.com/get_memes'.freeze
  PACK_NAME = 'Imgflip'.freeze
  STRIP_HEIGHT = 0.2

  Result = Data.define(:added, :skipped, :failed)

  DEFAULT_FETCHER = lambda do |url|
    response = Net::HTTP.get_response(URI(url))
    raise "Download failed (#{response.code}): #{url}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def self.import(fetcher: DEFAULT_FETCHER)
    payload = JSON.parse(fetcher.call(API_URL))
    raise "Imgflip API error: #{payload['error_message']}" unless payload['success']

    names = Template.pluck(:name).to_set { |name| normalize(name) }
    counts = Hash.new(0)
    payload.dig('data', 'memes').each { |meme| counts[import_meme(meme, names, fetcher)] += 1 }
    Result.new(added: counts[:added], skipped: counts[:skipped], failed: counts[:failed])
  end

  def self.import_meme(meme, names, fetcher)
    key = "imgflip-#{meme.fetch('id')}"
    name = meme.fetch('name').strip
    return :skipped if Template.exists?(memegen_id: key) || TemplateTombstone.buried?(key)
    return :skipped if names.include?(normalize(name))

    create_template(key, name, meme, fetcher)
    names << normalize(name)
    :added
  rescue StandardError => e
    Rails.logger.warn("Imgflip import skipped #{meme['id']}: #{e.message}")
    :failed
  end

  # Downloads first, so a failed download leaves no imageless Template behind.
  def self.create_template(key, name, meme, fetcher)
    url = meme.fetch('url')
    image = fetcher.call(url)
    Template.create!(memegen_id: key, name: name, source: url, source_kind: 'imgflip', pack: pack,
                     text_boxes: strips(meme.fetch('box_count').to_i)).tap do |template|
      template.image.attach(io: StringIO.new(image), filename: File.basename(URI(url).path))
    end
  end

  # Full-width strips stacked evenly from top to bottom: 2 boxes give the classic top and bottom.
  def self.strips(count)
    count = count.clamp(1, 10)
    return [TextBoxes::TOP_AND_BOTTOM.first.dup] if count == 1
    return TextBoxes::TOP_AND_BOTTOM.map(&:dup) if count == 2

    height = [STRIP_HEIGHT, 1.0 / count].min
    Array.new(count) do |i|
      TextBoxes::TOP_AND_BOTTOM.first.merge('y' => (i * (1.0 - height) / (count - 1)).round(4), 'h' => height.round(4))
    end
  end

  def self.pack
    Pack.where('lower(name) = ?', PACK_NAME.downcase).first || Pack.create!(name: PACK_NAME)
  end

  def self.normalize(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, '')
end
