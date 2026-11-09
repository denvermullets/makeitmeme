module Admin
  # Autosave endpoint: PATCH the whole ordered Text Box array as JSON, plus the Template's name when the editor has it.
  class TextBoxesController < BaseController
    def update
      template = Template.find(params[:template_id])
      body = request.request_parameters
      result = template.update_text_boxes(body['text_boxes'], name: body['name'])
      if result.valid?
        render json: { text_boxes: template.text_boxes, name: template.name, reviewed_at: template.reviewed_at }
      else
        render json: { errors: result.errors }, status: :unprocessable_content
      end
    end
  end
end
