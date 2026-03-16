# Rack::Timeout — protege threads do Puma contra requests que nunca terminam.
#
# Em produção, o processamento de planilhas grandes (especialmente o algoritmo
# combinatório) pode levar dezenas de segundos. O Render tem timeout de 120s
# (configurado via dashboard); o Rack::Timeout dispara em 90s para garantir
# que o Rails responde com mensagem amigável antes do Render retornar 502.
#
# Configuração do Render: Settings > Timeout > 120s
# ENV RACK_TIMEOUT_SERVICE_SECONDS — permite ajuste sem redeploy.

if Rails.env.production?
  # rack-timeout 0.7+ não tem setter de classe; o timeout é passado como opção
  # ao inserir o middleware. wait_timeout: 0 desabilita timeout de fila do Puma.
  Rails.application.config.middleware.use(
    Rack::Timeout,
    service_timeout: ENV.fetch("RACK_TIMEOUT_SERVICE_SECONDS", "90").to_i,
    wait_timeout: 0
  )
end
