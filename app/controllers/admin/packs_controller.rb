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
        refuse(pack.errors.full_messages, new_name: pack.name)
      end
    end

    def update
      if @pack.update(pack_params)
        redirect_to admin_packs_path, notice: "Renamed to #{@pack.name}"
      else
        refuse(@pack.errors.full_messages, renamed_id: @pack.id, renamed_name: @pack.name)
      end
    end

    # Pack#after_destroy removes the Pack from every Room's off list.
    def destroy
      if @pack.destroy
        redirect_to admin_packs_path, notice: "Deleted #{@pack.name}"
      else
        refuse(delete_errors)
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

    def refuse(errors, new_name: nil, renamed_id: nil, renamed_name: nil)
      @errors = errors
      @new_name = new_name
      @renamed_id = renamed_id
      @renamed_name = renamed_name
      load_packs
      render :index, status: :unprocessable_content
    end

    def load_packs
      @packs = Pack.left_joins(:templates).select('packs.*, COUNT(templates.id) AS templates_count')
                   .group('packs.id').order(Arel.sql('lower(packs.name)'))
    end
  end
end
