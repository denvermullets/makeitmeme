require 'test_helper'

class AdminImgflipImportTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test 'the Library offers Import from Imgflip' do
    sign_in_as_admin

    get admin_root_path

    assert_select 'form[action=?] button', admin_imgflip_import_path, 'Import from Imgflip'
  end

  test 'importing queues the job and lands on Needs review with a notice' do
    sign_in_as_admin

    assert_enqueued_with(job: ImportImgflipTemplatesJob) { post admin_imgflip_import_path }

    assert_redirected_to admin_root_path(filter: 'review')
    follow_redirect!
    assert_select '.notice', /Importing from Imgflip/
  end

  test 'signed-out visitors cannot import' do
    assert_no_enqueued_jobs { post admin_imgflip_import_path }
  end
end
