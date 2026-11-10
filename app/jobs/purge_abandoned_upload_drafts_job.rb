# Deletes Upload drafts last touched over about 24 hours ago and purges their images. Templates are never affected.
class PurgeAbandonedUploadDraftsJob < ApplicationJob
  CUTOFF = 24.hours

  def perform
    UploadDraft.where(updated_at: ...CUTOFF.ago).find_each do |draft|
      draft.image.purge
      draft.destroy
    end
  end
end
