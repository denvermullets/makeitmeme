# Runs ImgflipImport off the request, since it downloads up to ~100 images. Triggered from the Admin Library.
class ImportImgflipTemplatesJob < ApplicationJob
  def perform
    result = ImgflipImport.import
    Rails.logger.info("Imgflip import: #{result.added} added, #{result.skipped} skipped, #{result.failed} failed")
  end
end
