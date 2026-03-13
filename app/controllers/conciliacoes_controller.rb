require "securerandom"

class ConciliacoesController < ApplicationController
  protect_from_forgery with: :exception

  # GET /
  def new
  end

  # POST /upload
  def upload
    banco_file = params[:banco_file]
    erp_file   = params[:erp_file]

    unless banco_file.present? && erp_file.present?
      flash[:error] = "Por favor, envie os dois arquivos."
      return redirect_to root_path
    end

    uuid = SecureRandom.uuid
    dir  = tmp_dir(uuid)
    FileUtils.mkdir_p(dir)

    banco_path = File.join(dir, "banco#{File.extname(banco_file.original_filename)}")
    erp_path   = File.join(dir, "erp#{File.extname(erp_file.original_filename)}")

    File.binwrite(banco_path, banco_file.read)
    File.binwrite(erp_path,   erp_file.read)

    session[:uuid]       = uuid
    session[:banco_path] = banco_path
    session[:erp_path]   = erp_path

    redirect_to configurar_path
  end

  # GET /configurar
  def configurar
    @banco_path = session[:banco_path]
    @erp_path   = session[:erp_path]

    unless @banco_path && File.exist?(@banco_path)
      flash[:error] = "Sessão expirada. Faça o upload novamente."
      return redirect_to root_path
    end

    # Detecta cabeçalhos com linha padrão (9 para Sicredi .xls, 1 para ERP .xlsx)
    @banco_headers = safe_headers(@banco_path, 9)
    @erp_headers   = safe_headers(@erp_path, 1)
  end

  # POST /processar
  def processar
    banco_path = session[:banco_path]
    erp_path   = session[:erp_path]
    uuid       = session[:uuid]

    unless banco_path && File.exist?(banco_path)
      flash[:error] = "Sessão expirada. Faça o upload novamente."
      return redirect_to root_path
    end

    banco_config = {
      header_row: params[:banco_header_row],
      date_col:   params[:banco_date_col],
      value_col:  params[:banco_value_col],
      desc_col:   params[:banco_desc_col],
      doc_col:    params[:banco_doc_col]
    }

    erp_config = {
      header_row:  params[:erp_header_row],
      date_col:    params[:erp_date_col],
      valcred_col: params[:erp_valcred_col],
      valdeb_col:  params[:erp_valdeb_col],
      desc_col:    params[:erp_desc_col],
      doc_col:     params[:erp_doc_col],
      tp_col:      params[:erp_tp_col]
    }

    banco = PlanilhaReader.new(banco_path, banco_config).registros_banco
    erp   = PlanilhaReader.new(erp_path, erp_config).registros_erp

    resultado_alg1 = ConciliacaoService.new(banco, erp).executar
    resultado_alg2 = ConciliacaoDiariaService.new(
      resultado_alg1[:banco_sem_par],
      resultado_alg1[:erp_sem_par]
    ).executar
    resultado_alg3 = ConciliacaoCombinacaoService.new(
      resultado_alg2[:banco_sem_par],
      resultado_alg2[:erp_sem_par]
    ).executar

    dir = tmp_dir(uuid)
    RelatorioExportService.new(resultado_alg1, resultado_alg2, resultado_alg3, dir).gerar

    @stats_alg1 = resultado_alg1[:stats]
    @stats_alg2 = resultado_alg2[:stats]
    @stats_alg3 = resultado_alg3[:stats]
    @uuid       = uuid
  rescue ArgumentError => e
    flash[:error] = "Erro de configuração: #{e.message}"
    redirect_to configurar_path
  rescue => e
    flash[:error] = "Erro ao processar: #{e.message}"
    redirect_to configurar_path
  end

  # GET /download/:uuid/:tipo
  def download
    uuid = params[:uuid]
    tipo = params[:tipo]

    unless %w[conciliados pendentes].include?(tipo)
      return head :not_found
    end

    path = File.join(tmp_dir(uuid), "#{tipo}.xlsx")

    unless File.exist?(path)
      return head :not_found
    end

    send_file path,
      filename: "#{tipo}.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      disposition: "attachment"
  end

  private

  def tmp_dir(uuid)
    Rails.root.join("tmp", "conciliacao", uuid).to_s
  end

  def safe_headers(path, default_row)
    PlanilhaReader.read_headers(path, default_row)
  rescue
    []
  end
end
