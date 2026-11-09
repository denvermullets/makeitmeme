module Admin
  class TemplatesController < BaseController
    include LibraryState

    before_action :set_template, only: %i[update review]

    # Renaming or moving to another Pack never touches reviewed_at or hidden_at.
    def update
      if @template.update(template_changes)
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
      redirect_to admin_root_path(q: params[:q].presence, pack: params[:pack].presence), status: :see_other
    end

    private

    def template_changes
      attrs = params.fetch(:template, {})
      changes = {}
      changes[:name] = attrs[:name].to_s.strip if attrs.key?(:name)
      changes[:pack] = Pack.find(attrs[:pack_id]) if attrs[:pack_id].present?
      changes
    end

    def set_template
      @template = Template.find(params[:id])
    end
  end
end
