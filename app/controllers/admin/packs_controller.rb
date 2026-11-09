module Admin
  class PacksController < BaseController
    def index
      @packs = Pack.left_joins(:templates).select('packs.*, COUNT(templates.id) AS templates_count')
                   .group('packs.id').order(Arel.sql('lower(packs.name)'))
    end
  end
end
