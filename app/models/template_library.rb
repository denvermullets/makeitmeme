require 'net/http'

# Seeds the Template Library from a committed JSON manifest (no images in git).
# Upserts by memegen id; an image is downloaded only for Templates that lack one.
module TemplateLibrary
  DEFAULT_MANIFEST = Rails.root.join('db/templates_manifest.json')

  DEFAULT_FETCHER = lambda do |url|
    response = Net::HTTP.get_response(URI(url))
    raise "Download failed (#{response.code}): #{url}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def self.import(manifest_path = DEFAULT_MANIFEST, fetcher: DEFAULT_FETCHER)
    JSON.parse(File.read(manifest_path)).each do |entry|
      template = Template.find_or_initialize_by(memegen_id: entry.fetch('id'))
      template.source_kind = 'memegen' if template.new_record?
      template.update!(name: entry.fetch('name'), source: entry['source'], text_boxes: entry.fetch('text_boxes'))
      next if template.image.attached?

      url = entry.fetch('image_url')
      template.image.attach(io: StringIO.new(fetcher.call(url)), filename: File.basename(URI(url).path))
    end
  end
end
