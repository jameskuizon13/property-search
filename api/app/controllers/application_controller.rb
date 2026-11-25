class ApplicationController < ActionController::API
  # Every error response uses the same envelope:
  #   { "error": { "code": "...", "message": "...", "details": {...} } }
  # Errors raised outside a controller (unknown routes, crashes) get the same
  # shape from JsonExceptionsApp in production.
  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error :not_found, "not_found", "#{e.model || 'Record'} not found"
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error :unprocessable_content, "validation_failed", "Validation failed", e.record.errors.to_hash
  end

  # Query objects (e.g. Properties::SearchQuery) that fail validate!.
  rescue_from ActiveModel::ValidationError do |e|
    render_error :unprocessable_content, "validation_failed", "Validation failed", e.model.errors.to_hash
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_error :bad_request, "parameter_missing", e.message
  end

  rescue_from ActionController::BadRequest do |e|
    render_error :bad_request, "bad_request", e.message
  end

  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render_error :bad_request, "bad_request", "Request body is not valid JSON"
  end

  private

  # details keys are camelized like every other JSON key, so a field error
  # lines up with the param or attribute the client sent (maxPrice, not max_price).
  def render_error(status, code, message, details = nil)
    body = { code:, message: }
    body[:details] = details.transform_keys { |key| key.to_s.camelize(:lower) } if details.present?
    render json: { error: body }, status:
  end

  # Permitted params arrive as any JSON scalar; models expect strings.
  # Returns the permitted hash, or raises 400 if a value is neither a string
  # nor null, or contains a NUL byte (bcrypt and Postgres both reject those).
  # Null is left to model validations ("can't be blank").
  def string_params(*keys)
    permitted = params.permit(*keys)
    permitted.each do |key, value|
      next if value.nil?
      raise ActionController::BadRequest, "#{key} must be a string" unless value.is_a?(String)
      raise ActionController::BadRequest, "#{key} contains a null byte" if value.include?("\u0000")
    end
    permitted
  end
end
