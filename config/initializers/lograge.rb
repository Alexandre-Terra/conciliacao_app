# Logs estruturados JSON para o Render Log Explorer.
# Cada request gera UMA linha JSON em vez do bloco multilinha padrão do Rails.
#
# Campos padrão do lograge: method, path, format, controller, action, status, duration, db, view
# Campos adicionados abaixo: request_id, error, message, backtrace (em caso de exceção)

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  # Logger dedicado sem TaggedLogging para que a linha de request seja JSON puro.
  # Logs de Rails.logger (services, etc.) ainda passam pelo logger principal com [request_id].
  config.lograge.logger = ActiveSupport::Logger.new($stdout)

  # Campos adicionais vindos do contexto do controller
  config.lograge.custom_payload do |controller|
    { request_id: controller.request.request_id }
  end

  # Campos adicionais vindos do payload do evento (exceções)
  config.lograge.custom_options = lambda do |event|
    ex = event.payload[:exception_object]
    return {} unless ex

    {
      error:     ex.class.name,
      message:   ex.message,
      backtrace: ex.backtrace&.first(5)
    }
  end
end
