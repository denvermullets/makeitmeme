module Admin
  class TemplatesController < BaseController
    include LibraryState

    before_action :set_template, only: %i[update review]

    # Renaming never touches reviewed_at.
    def update
      if @template.update(name: params.dig(:template, :name).to_s.strip)
        redirect_to admin_root_path(library_params(@template.id)), status: :see_other
      else
        load_library(selected: @template.id)
        @template_errors = @template.errors.full_messages
        render 'admin/homes/show', status: :unprocessable_content
      end
    end

    # Mark reviewed changes nothing but reviewed_at.
    def review
      @template.update_column(:reviewed_at, Time.current) if @template.reviewed_at.nil?
      redirect_to admin_root_path(library_params(@template.id)), status: :see_other
    end

    # Hard delete (ADR 0002): the image is purged and Memes keep their baked image with template_id nulled.
    def destroy
      Template.find(params[:id]).destroy!
      redirect_to admin_root_path(q: params[:q].presence), status: :see_other
    end

    private

    def set_template
      @template = Template.find(params[:id])
    end
  end
end
