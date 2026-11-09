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
    ensure_system_packs
    JSON.parse(File.read(manifest_path)).each { |entry| import_entry(entry, fetcher) }
  end

  def self.import_entry(entry, fetcher)
    template = Template.find_or_initialize_by(memegen_id: entry.fetch('id'))
    template.update!(name: entry.fetch('name'), source: entry['source'], text_boxes: entry.fetch('text_boxes'),
                     pack: pack_for(entry['pack']))
    return if template.image.attached?

    url = entry.fetch('image_url')
    template.image.attach(io: StringIO.new(fetcher.call(url)), filename: File.basename(URI(url).path))
  end

  def self.ensure_system_packs
    Pack.custom
    Pack.classics
  end

  def self.pack_for(name)
    return Pack.classics if name.blank?

    Pack.where('lower(name) = ?', name.downcase).first || Pack.create!(name: name)
  end
end
