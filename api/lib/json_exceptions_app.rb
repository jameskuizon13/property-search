# Renders errors that never reach a controller's rescue_from (unknown routes,
# unhandled exceptions) in the API's shared error envelope instead of HTML.
# Wired up as config.exceptions_app; Rails calls it with PATH_INFO "/<status>".
class JsonExceptionsApp
  CODES = {
    400 => "bad_request",
    404 => "not_found",
    405 => "method_not_allowed",
    406 => "not_acceptable",
    422 => "validation_failed",
    500 => "internal_error"
  }.freeze

  def call(env)
    status = env["PATH_INFO"].to_s.delete_prefix("/").to_i
    status = 500 unless status.between?(400, 599)
    message = Rack::Utils::HTTP_STATUS_CODES.fetch(status, "Error")
    code = CODES.fetch(status) { message.parameterize(separator: "_") }
    body = { error: { code:, message: } }.to_json
    headers = { "content-type" => "application/json; charset=utf-8", "x-content-type-options" => "nosniff" }
    [ status, headers, [ body ] ]
  end
end
