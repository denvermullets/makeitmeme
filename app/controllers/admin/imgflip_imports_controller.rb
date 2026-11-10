module Admin
  # "Import from Imgflip": queues the import; new Templates show up under Needs review in the Imgflip Pack.
  class ImgflipImportsController < BaseController
    NOTICE = 'Importing from Imgflip. New Templates appear under Needs review in a minute.'.freeze

    def create
      ImportImgflipTemplatesJob.perform_later
      redirect_to admin_root_path(filter: 'review'), status: :see_other, notice: NOTICE
    end
  end
end
