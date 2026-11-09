require 'net/http'

# Seeds the Template Library from a committed JSON manifest (no images in git).
# Idempotent by memegen id (insert-only); an image is downloaded only for Templates that lack one.
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

  # Creates a Template only for a memegen id never seen (and not tombstoned). Existing Templates are
  # never updated, so Admin curation (boxes, name, Pack, hidden/reviewed state) survives a re-seed.
  def self.import_entry(entry, fetcher)
    memegen_id = entry.fetch('id')
    return if TemplateTombstone.buried?(memegen_id)

    template = Template.find_by(memegen_id: memegen_id) || create_template(memegen_id, entry)
    return if template.image.attached?

    url = entry.fetch('image_url')
    template.image.attach(io: StringIO.new(fetcher.call(url)), filename: File.basename(URI(url).path))
  end

  def self.create_template(memegen_id, entry)
    Template.create!(memegen_id: memegen_id, name: entry.fetch('name'), source: entry['source'],
                     text_boxes: entry.fetch('text_boxes'), pack: pack_for(entry['pack']),
                     source_kind: 'memegen')
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
