module Admin
  # Autosave endpoint: PATCH the whole ordered Text Box array as JSON.
  class TextBoxesController < BaseController
    def update
      template = Template.find(params[:template_id])
      result = template.update_text_boxes(request.request_parameters['text_boxes'])
      if result.valid?
        render json: { text_boxes: template.text_boxes, reviewed_at: template.reviewed_at }
      else
        render json: { errors: result.errors }, status: :unprocessable_content
      end
    end
  end
end
