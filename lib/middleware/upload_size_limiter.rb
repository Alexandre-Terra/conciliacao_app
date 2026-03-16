# Rack-level guard: rejects multipart upload requests whose Content-Length
# exceeds the configured limit before the request body is fully buffered.
class UploadSizeLimiter
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"] == "/upload" && env["REQUEST_METHOD"] == "POST"
      max_bytes = ENV.fetch("MAX_UPLOAD_SIZE_MB", "20").to_i * 1_024 * 1_024
      content_length = env["CONTENT_LENGTH"].to_i

      if content_length > max_bytes
        mb = ENV.fetch("MAX_UPLOAD_SIZE_MB", "20")
        body = "Arquivo excede o tamanho máximo de #{mb}MB."
        return [ 413, { "Content-Type" => "text/plain; charset=utf-8" }, [ body ] ]
      end
    end

    @app.call(env)
  end
end
