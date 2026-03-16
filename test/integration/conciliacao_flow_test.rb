require "test_helper"

# Testa o fluxo HTTP ponta a ponta: upload → configurar → processar → download.
#
# Os fixtures XLSX são gerados em memória a cada teste com caxlsx (já no Gemfile).
# Banco: 2 registros em datas distintas | ERP: 2 registros com valores idênticos
# → Alg1 casa 100% → taxa_conciliacao_banco = 100.0
class ConciliacaoFlowTest < ActionDispatch::IntegrationTest
  XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  def setup
    @banco_file    = build_banco_xlsx
    @erp_file      = build_erp_xlsx
    @uploaded_uuid = nil
  end

  def teardown
    [@banco_file, @erp_file].each { |f| f.close rescue nil; f.unlink rescue nil }
    FileUtils.rm_rf(Rails.root.join("tmp", "conciliacao", @uploaded_uuid)) if @uploaded_uuid
  end

  # ── Happy path — cada passo individualmente ──────────────────────────────

  test "upload com arquivos validos redireciona para configurar e salva sessao" do
    do_upload
    assert_redirected_to configurar_path
    assert_not_nil session[:uuid]
    assert_not_nil session[:banco_path]
    assert_not_nil session[:erp_path]
    assert File.exist?(session[:banco_path])
    assert File.exist?(session[:erp_path])
  end

  test "configurar exibe formulario de mapeamento de colunas" do
    do_upload
    get configurar_path
    assert_response :success
    assert_select "input[name='banco_header_row']"
    assert_select "input[name='banco_date_col']"
    assert_select "input[name='erp_date_col']"
    assert_select "input[name='erp_valcred_col']"
    assert_select "form[action=?]", processar_path
  end

  test "processar concilia registros e exibe estatisticas corretas" do
    do_upload
    post processar_path, params: processar_params
    assert_response :success
    # Fixture: 2 banco + 2 erp, casamento exato → taxa = 100%
    assert_match "100.0%", response.body
    assert_select ".stat-label", text: "Total Banco"
    assert_select ".stat-label", text: "Conciliados"
    # Links de download gerados com o uuid correto
    assert_select "a[href*='conciliados']"
    assert_select "a[href*='pendentes']"
  end

  test "download de conciliados retorna xlsx com assinatura PK valida" do
    do_upload
    post processar_path, params: processar_params
    get download_path(uuid: @uploaded_uuid, tipo: "conciliados")
    assert_response :success
    assert_equal XLSX_MIME, response.content_type
    assert response.body.bytesize > 0
    assert_equal "PK", response.body.byteslice(0, 2), "Esperado ZIP/XLSX com assinatura PK"
  end

  test "download de pendentes retorna xlsx com assinatura PK valida" do
    do_upload
    post processar_path, params: processar_params
    get download_path(uuid: @uploaded_uuid, tipo: "pendentes")
    assert_response :success
    assert_equal XLSX_MIME, response.content_type
    assert_equal "PK", response.body.byteslice(0, 2)
  end

  # ── Happy path — fluxo completo de ponta a ponta ─────────────────────────

  test "fluxo completo upload -> configurar -> processar -> download" do
    # 1. Upload
    post upload_path, params: { banco_file: xlsx_upload(@banco_file), erp_file: xlsx_upload(@erp_file) }
    assert_redirected_to configurar_path
    uuid = session[:uuid]
    assert_not_nil uuid

    # 2. Configurar
    follow_redirect!
    assert_response :success
    assert_select "input[name='banco_header_row']"

    # 3. Processar
    post processar_path, params: processar_params
    assert_response :success
    assert_match "100.0%", response.body

    # 4. Download conciliados
    get download_path(uuid: uuid, tipo: "conciliados")
    assert_response :success
    assert_equal XLSX_MIME, response.content_type
    assert_equal "PK", response.body.byteslice(0, 2)

    # 5. Download pendentes
    get download_path(uuid: uuid, tipo: "pendentes")
    assert_response :success
    assert_equal XLSX_MIME, response.content_type
  end

  # ── Cenários de erro ──────────────────────────────────────────────────────

  test "upload sem nenhum arquivo redireciona para root com flash error" do
    post upload_path, params: {}
    assert_redirected_to root_path
    assert_equal "Por favor, envie os dois arquivos.", flash[:error]
  end

  test "upload apenas com banco_file redireciona para root com flash error" do
    post upload_path, params: { banco_file: xlsx_upload(@banco_file) }
    assert_redirected_to root_path
    assert_equal "Por favor, envie os dois arquivos.", flash[:error]
  end

  test "upload com content_type invalido redireciona com flash error" do
    txt = Tempfile.new(["fake", ".xlsx"])
    txt.write("conteúdo não é xlsx"); txt.flush
    post upload_path, params: {
      banco_file: fixture_file_upload(txt.path, "text/plain"),
      erp_file:   xlsx_upload(@erp_file)
    }
    assert_redirected_to root_path
    assert_match(/inválido/i, flash[:error])
  ensure
    txt&.close; txt&.unlink
  end

  test "configurar sem sessao redireciona para root com flash error" do
    get configurar_path
    assert_redirected_to root_path
    assert_match(/expirada/i, flash[:error])
  end

  test "processar sem sessao redireciona para root com flash error" do
    post processar_path, params: processar_params
    assert_redirected_to root_path
    assert_match(/expirada/i, flash[:error])
  end

  test "download com uuid inexistente retorna 404" do
    get download_path(uuid: "00000000-0000-0000-0000-000000000000", tipo: "conciliados")
    assert_response :not_found
  end

  test "download com tipo invalido retorna 404" do
    get download_path(uuid: SecureRandom.uuid, tipo: "script_injetado")
    assert_response :not_found
  end

  private

  # Executa o upload e captura o uuid da sessão para cleanup no teardown.
  def do_upload
    post upload_path, params: { banco_file: xlsx_upload(@banco_file), erp_file: xlsx_upload(@erp_file) }
    @uploaded_uuid = session[:uuid]
  end

  def xlsx_upload(tempfile)
    fixture_file_upload(tempfile.path, XLSX_MIME)
  end

  # Parâmetros do /processar mapeados para as colunas dos fixtures gerados abaixo.
  # banco_header_row=1 porque o fixture tem cabeçalhos na linha 1 (não linha 9 do Sicredi).
  def processar_params
    {
      banco_header_row: "1",
      banco_date_col:   "Data",
      banco_value_col:  "Valor",
      banco_desc_col:   "Descricao",
      banco_doc_col:    "",
      erp_header_row:   "1",
      erp_date_col:     "Data",
      erp_valcred_col:  "ValCred",
      erp_valdeb_col:   "ValDeb",
      erp_desc_col:     "Historico",
      erp_doc_col:      "",
      erp_tp_col:       ""
    }
  end

  # Fixture banco: 2 registros que casam exatamente com os registros ERP.
  # Resultado esperado: Alg1 concilia 2/2 → taxa = 100.0%
  def build_banco_xlsx
    tmp = Tempfile.new(["banco_test", ".xlsx"])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Banco") do |sheet|
        sheet.add_row(["Data", "Valor", "Descricao", "Documento"])
        sheet.add_row([Date.new(2025, 1, 10), 100.0, "Transferencia TED", "DOC001"])
        sheet.add_row([Date.new(2025, 1, 11), 200.0, "Pagamento boleto",  "DOC002"])
      end
      p.serialize(tmp.path)
    end
    tmp
  end

  # Fixture ERP: 2 registros (valcred - valdeb = 100 e 200) nas mesmas datas do banco.
  def build_erp_xlsx
    tmp = Tempfile.new(["erp_test", ".xlsx"])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "ERP") do |sheet|
        sheet.add_row(["Data", "ValCred", "ValDeb", "Historico", "Documento", "TP"])
        sheet.add_row([Date.new(2025, 1, 10), 100.0, 0.0, "Credito extrato", "DOC001", "C"])
        sheet.add_row([Date.new(2025, 1, 11), 200.0, 0.0, "Credito extrato", "DOC002", "C"])
      end
      p.serialize(tmp.path)
    end
    tmp
  end
end
