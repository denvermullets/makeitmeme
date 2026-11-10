namespace :templates do
  desc 'Seed the Template Library from db/templates_manifest.json (idempotent; downloads only missing images)'
  task seed: :environment do
    TemplateLibrary.import
    puts "Template Library: #{Template.count} Templates"
  end

  desc "Add Imgflip's current top memes to the Imgflip Pack (idempotent; skips imported/deleted/same-name)"
  task import_imgflip: :environment do
    result = ImgflipImport.import
    puts "Imgflip: #{result.added} added, #{result.skipped} skipped, #{result.failed} failed"
  end
end
