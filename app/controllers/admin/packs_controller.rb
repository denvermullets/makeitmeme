module Admin
  class PacksController < BaseController
    before_action :set_pack, only: %i[update destroy]

    def index
      load_packs
    end

    def create
      pack = Pack.new(pack_params)
      if pack.save
        redirect_to admin_packs_path, notice: "Created #{pack.name}"
      else
        render_index_with_errors(pack)
      end
    end

    def update
      if @pack.update(pack_params)
        redirect_to admin_packs_path, notice: "Renamed to #{@pack.name}"
      else
        render_index_with_errors(@pack)
      end
    end

    # Pack#after_destroy removes the Pack from every Room's off list.
    def destroy
      if @pack.destroy
        redirect_to admin_packs_path, notice: "Deleted #{@pack.name}"
      else
        render_index_with_errors(@pack, delete_errors)
      end
    end

    private

    def set_pack
      @pack = Pack.find(params[:id])
    end

    def pack_params
      params.expect(pack: [:name])
    end

    def delete_errors
      return ['The Custom Pack cannot be deleted'] if @pack.custom?

      ["#{@pack.name} still has Templates. Move or delete them first."]
    end

    # Re-renders the index with the Pack that failed, so the view can keep what the Admin typed.
    def render_index_with_errors(pack, errors = pack.errors.full_messages)
      @errors = errors
      @failed_pack = pack
      load_packs
      render :index, status: :unprocessable_content
    end

    def load_packs
      @packs = Pack.left_joins(:templates).select('packs.*, COUNT(templates.id) AS templates_count')
                   .group('packs.id').alphabetical
    end
  end
end
