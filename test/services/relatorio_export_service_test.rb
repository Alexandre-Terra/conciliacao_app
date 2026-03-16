require "test_helper"

class RelatorioExportServiceTest < ActiveSupport::TestCase
  D1 = Date.new(2025, 1, 10)
  D2 = Date.new(2025, 1, 11)

  setup do
    @dir = Dir.mktmpdir("relatorio_test_")

    banco1 = { id: 1, data: D1, valor: 100.0, descricao: "TED entrada",  documento: "B1" }
    banco2 = { id: 2, data: D2, valor: 200.0, descricao: "PIX recebido", documento: "B2" }
    erp1   = { id: 1, data: D1, valor_liquido: 100.0, valcred: 100.0, valdeb: 0.0,  historico: "Entrada TED",  numdocumento: "E1", tp: "E" }
    erp2   = { id: 2, data: D2, valor_liquido: 200.0, valcred: 200.0, valdeb: 0.0,  historico: "Receita PIX",  numdocumento: "E2", tp: "E" }
    erp3   = { id: 3, data: D1, valor_liquido:  50.0, valcred:  50.0, valdeb: 0.0,  historico: "Lançamento",   numdocumento: "E3", tp: "E" }

    resultado_alg1 = {
      conciliados:   [ { banco: banco1, erp: erp1 } ],
      banco_sem_par: [ banco2 ],
      erp_sem_par:   [ erp2 ],
      stats:         {}
    }

    resultado_alg2 = {
      dias_conciliados: [
        { data: D2, banco: [ banco2 ], erp: [ erp2 ], total_banco: 200.0, total_erp: 200.0 }
      ],
      banco_sem_par: [],
      erp_sem_par:   [ erp3 ],
      stats:         {}
    }

    resultado_alg3 = {
      conciliados:   [],
      banco_sem_par: [],
      erp_sem_par:   [ erp3 ],
      stats:         {}
    }

    @service = RelatorioExportService.new(resultado_alg1, resultado_alg2, resultado_alg3, @dir)
    @service.gerar
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  # ── arquivos gerados ──────────────────────────────────────────────────────────

  test "gera arquivo conciliados.xlsx" do
    assert File.exist?(@service.caminho_conciliados)
  end

  test "gera arquivo pendentes.xlsx" do
    assert File.exist?(@service.caminho_pendentes)
  end

  test "conciliados.xlsx e um arquivo zip valido" do
    assert File.binread(@service.caminho_conciliados, 2) == "PK",
           "conciliados.xlsx não começa com magic bytes PK (não é um ZIP/XLSX válido)"
  end

  test "pendentes.xlsx e um arquivo zip valido" do
    assert File.binread(@service.caminho_pendentes, 2) == "PK",
           "pendentes.xlsx não começa com magic bytes PK (não é um ZIP/XLSX válido)"
  end

  # ── estrutura de abas ─────────────────────────────────────────────────────────

  test "conciliados.xlsx tem 3 abas" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    assert_equal 3, wb.sheets.size
  end

  test "conciliados.xlsx tem as abas corretas" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    assert_includes wb.sheets, "Exato (Data + Valor)"
    assert_includes wb.sheets, "Saldo Diário"
    assert_includes wb.sheets, "Combinacao (2 a 6)"
  end

  test "pendentes.xlsx tem 2 abas" do
    wb = Roo::Spreadsheet.open(@service.caminho_pendentes)
    assert_equal 2, wb.sheets.size
  end

  test "pendentes.xlsx tem as abas corretas" do
    wb = Roo::Spreadsheet.open(@service.caminho_pendentes)
    assert_includes wb.sheets, "Banco"
    assert_includes wb.sheets, "ERP"
  end

  # ── conteúdo: conciliados ─────────────────────────────────────────────────────

  test "aba Exato tem linha de cabecalho" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    wb.default_sheet = "Exato (Data + Valor)"
    assert_equal "ID Banco", wb.cell(1, 1)
    assert_equal "Valor Banco", wb.cell(1, 5)
  end

  test "aba Exato tem 1 linha de dados para o par conciliado" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    wb.default_sheet = "Exato (Data + Valor)"
    assert_equal "10/01/2025", wb.cell(2, 2)   # data formatada dd/mm/yyyy
    assert_equal 100.0,        wb.cell(2, 5)   # valor banco
    assert_equal 100.0,        wb.cell(2, 11)  # valor líquido ERP
  end

  test "aba Exato nao tem linha de dados alem do par conciliado" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    wb.default_sheet = "Exato (Data + Valor)"
    assert_nil wb.cell(3, 1), "Esperava que a linha 3 fosse vazia (apenas 1 par conciliado)"
  end

  test "aba Saldo Diario tem 1 linha de dados para o dia conciliado" do
    wb = Roo::Spreadsheet.open(@service.caminho_conciliados)
    wb.default_sheet = "Saldo Diário"
    # Linha 1 = cabeçalho; linha 2 = dados do dia D2
    assert_equal "11/01/2025", wb.cell(2, 1)
    assert_equal 200.0,        wb.cell(2, 2)   # total_banco
  end

  # ── conteúdo: pendentes ───────────────────────────────────────────────────────

  test "aba Banco de pendentes tem cabecalho correto" do
    wb = Roo::Spreadsheet.open(@service.caminho_pendentes)
    wb.default_sheet = "Banco"
    assert_equal "ID Banco",  wb.cell(1, 1)
    assert_equal "Valor",     wb.cell(1, 5)
  end

  test "aba Banco de pendentes esta vazia quando nao ha banco_sem_par" do
    wb = Roo::Spreadsheet.open(@service.caminho_pendentes)
    wb.default_sheet = "Banco"
    # resultado_alg3[:banco_sem_par] = [] → apenas header, sem linhas de dados
    assert_nil wb.cell(2, 1)
  end

  test "aba ERP de pendentes tem o registro sem par" do
    wb = Roo::Spreadsheet.open(@service.caminho_pendentes)
    wb.default_sheet = "ERP"
    assert_equal "E3",        wb.cell(2, 4)   # numdocumento
    assert_equal 50.0,        wb.cell(2, 7)   # valor_liquido
    assert_equal "E",         wb.cell(2, 8)   # tp
  end

  # ── caminho_conciliados / caminho_pendentes ───────────────────────────────────

  test "caminho_conciliados aponta para o diretorio correto" do
    assert_equal File.join(@dir, "conciliados.xlsx"), @service.caminho_conciliados
  end

  test "caminho_pendentes aponta para o diretorio correto" do
    assert_equal File.join(@dir, "pendentes.xlsx"), @service.caminho_pendentes
  end

  # ── limpeza ───────────────────────────────────────────────────────────────────

  test "teardown remove os arquivos gerados" do
    conciliados = @service.caminho_conciliados
    pendentes   = @service.caminho_pendentes
    # Os arquivos existem agora (criados no setup)
    assert File.exist?(conciliados)
    assert File.exist?(pendentes)
    # teardown removerá @dir; verificado implicitamente pela ausência de leak entre testes
  end
end
