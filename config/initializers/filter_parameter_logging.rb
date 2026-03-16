# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# LGPD: arquivos bancários não devem expor metadados internos nos logs (path do tempfile, headers).
# Substitui o inspect padrão do UploadedFile por um resumo seguro que preserva
# o nome do arquivo e o tamanho para debug, sem expor internals do servidor.
#
# Parâmetros de configuração de colunas (banco_date_col, erp_valcred_col, etc.)
# não são sensíveis e permanecem nos logs normalmente.
Rails.application.config.filter_parameters += [
  lambda do |key, value|
    if %w[banco_file erp_file].include?(key) && value.respond_to?(:original_filename)
      value.define_singleton_method(:inspect) do
        "#<UploadedFile filename=#{original_filename.inspect} size=#{size} content_type=#{content_type.inspect}>"
      end
    end
  end
]
