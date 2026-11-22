class ApplicationController < ActionController::API
  # Every error response uses the same envelope:
  #   { "error": { "code": "...", "message": "...", "details": {...} } }
  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error :not_found, "not_found", "#{e.model || 'Record'} not found"
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error :unprocessable_content, "validation_failed", "Validation failed", e.record.errors.to_hash
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_error :bad_request, "parameter_missing", e.message
  end

  private

  def render_error(status, code, message, details = nil)
    body = { code:, message: }
    body[:details] = details if details.present?
    render json: { error: body }, status:
  end
end
