module Admin
  class BaseController < ApplicationController
    include AdminSession

    layout 'admin'
  end
end
