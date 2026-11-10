require 'test_helper'

class PurgeAbandonedUploadDraftsJobTest < ActiveSupport::TestCase
  test 'deletes drafts older than the cutoff and removes their image blob' do
    draft = start_upload_draft(token: 'old', nickname: 'Ann')
    blob = draft.image.blob

    travel_to(25.hours.from_now) { PurgeAbandonedUploadDraftsJob.perform_now }

    assert_not UploadDraft.exists?(draft.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test 'keeps drafts newer than the cutoff' do
    draft = start_upload_draft(token: 'new', nickname: 'Ann')

    travel_to(23.hours.from_now) { PurgeAbandonedUploadDraftsJob.perform_now }

    assert UploadDraft.exists?(draft.id)
  end

  test 'leaves Templates alone, including ones made from drafts' do
    draft = start_upload_draft(token: 'tok', nickname: 'Ann')
    draft.update!(name: 'Mine')
    template = Upload.add_to_library(draft)
    blob = template.image.blob

    travel_to(48.hours.from_now) { PurgeAbandonedUploadDraftsJob.perform_now }

    assert Template.exists?(template.id)
    assert ActiveStorage::Blob.exists?(blob.id)
  end

  test 'is scheduled in every environment' do
    config = YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true)

    %w[development test production].each do |env|
      assert(config.fetch(env).values.any? { |t| t['class'] == 'PurgeAbandonedUploadDraftsJob' }, env)
    end
  end
end
