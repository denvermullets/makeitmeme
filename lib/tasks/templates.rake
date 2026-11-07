namespace :templates do
  desc 'Seed the Template Library from db/templates_manifest.json (idempotent; downloads only missing images)'
  task seed: :environment do
    TemplateLibrary.import
    puts "Template Library: #{Template.count} Templates"
  end
end
