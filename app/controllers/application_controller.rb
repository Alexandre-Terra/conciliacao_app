class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Rack::Timeout::RequestTimeoutException herda de Exception (não StandardError),
  # então não é capturado por `rescue => e`. Este rescue_from garante resposta
  # amigável caso o timeout ocorra em qualquer action.
  rescue_from Rack::Timeout::RequestTimeoutException do
    flash[:error] = "O processamento excedeu o tempo limite. " \
                    "Tente com planilhas menores ou reduza o número de registros."
    redirect_to(request.referer || root_path)
  end
end
