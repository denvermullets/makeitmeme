module Admin
  class HomesController < BaseController
    include LibraryState

    def show
      load_library
    end
  end
end
