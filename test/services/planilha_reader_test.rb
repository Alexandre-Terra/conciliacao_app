require "test_helper"

class PlanilhaReaderTest < ActiveSupport::TestCase
  BANCO_CONFIG = {
    header_row: 1,
    date_col:   "Data",
    value_col:  "Valor (R$)",
    desc_col:   "Descrição",
    doc_col:    "Documento"
  }.freeze

  ERP_CONFIG = {
    header_row:  1,
    date_col:    "DATA",
    valcred_col: "VALCRED",
    valdeb_col:  "VALDEB",
    desc_col:    "HISTORICO",
    doc_col:     "NUMDOCUMENTO",
    tp_col:      "TP"
  }.freeze

  D1 = Date.new(2025, 1, 10)
  D2 = Date.new(2025, 1, 11)

  # ── registros_banco ──────────────────────────────────────────────────────────

  test "le banco xlsx e retorna 3 registros validos" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    assert_equal 3, registros.size
  end

  test "le banco xls e retorna 3 registros validos" do
    registros = reader("banco_test.xls", BANCO_CONFIG).registros_banco
    assert_equal 3, registros.size
  end

  test "banco xlsx ignora linha sem data" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    # fixture tem 4 linhas de dados; a 4ª tem data nil → ignorada
    assert_equal 3, registros.size
    refute registros.any? { |r| r[:documento] == "DOC004" }
  end

  test "banco xlsx retorna datas como Date" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    registros.each { |r| assert_instance_of Date, r[:data] }
  end

  test "banco xls converte string iso para Date" do
    registros = reader("banco_test.xls", BANCO_CONFIG).registros_banco
    registros.each { |r| assert_instance_of Date, r[:data] }
  end

  test "banco xlsx retorna datas corretas" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    assert_equal D1, registros[0][:data]
    assert_equal D1, registros[1][:data]
    assert_equal D2, registros[2][:data]
  end

  test "banco xls retorna datas corretas" do
    registros = reader("banco_test.xls", BANCO_CONFIG).registros_banco
    assert_equal D1, registros[0][:data]
    assert_equal D2, registros[2][:data]
  end

  test "banco xlsx retorna valores float corretos" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    assert_equal 100.0,  registros[0][:valor]
    assert_equal 200.5,  registros[2][:valor]
  end

  test "banco xlsx normaliza valor com virgula para float" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    r = registros.find { |r| r[:documento] == "DOC002" }
    assert_in_delta 1234.56, r[:valor], 0.001
  end

  test "banco xls normaliza valor com virgula para float" do
    registros = reader("banco_test.xls", BANCO_CONFIG).registros_banco
    r = registros.find { |r| r[:documento] == "DOC002" }
    assert_in_delta 1234.56, r[:valor], 0.001
  end

  test "banco xlsx retorna descricao e documento corretos" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    assert_equal "Transferência TED", registros[0][:descricao]
    assert_equal "DOC001",            registros[0][:documento]
  end

  test "banco xlsx atribui id sequencial a partir de 1" do
    registros = reader("banco_test.xlsx", BANCO_CONFIG).registros_banco
    assert_equal [1, 2, 3], registros.map { |r| r[:id] }
  end

  # ── registros_erp ────────────────────────────────────────────────────────────

  test "le erp xlsx e retorna 3 registros validos" do
    registros = reader("erp_test.xlsx", ERP_CONFIG).registros_erp
    assert_equal 3, registros.size
  end

  test "le erp xls e retorna 3 registros validos" do
    registros = reader("erp_test.xls", ERP_CONFIG).registros_erp
    assert_equal 3, registros.size
  end

  test "erp xlsx calcula valor_liquido para credito" do
    registros = reader("erp_test.xlsx", ERP_CONFIG).registros_erp
    r = registros.find { |r| r[:numdocumento] == "NF001" }
    assert_in_delta 100.0, r[:valor_liquido], 0.001   # 100 - 0
    assert_in_delta 100.0, r[:valcred],       0.001
    assert_in_delta   0.0, r[:valdeb],        0.001
  end

  test "erp xlsx calcula valor_liquido negativo para debito" do
    registros = reader("erp_test.xlsx", ERP_CONFIG).registros_erp
    r = registros.find { |r| r[:numdocumento] == "NF002" }
    assert_in_delta(-50.0, r[:valor_liquido], 0.001)  # 0 - 50
  end

  test "erp xlsx retorna historico e tp corretos" do
    registros = reader("erp_test.xlsx", ERP_CONFIG).registros_erp
    r = registros.find { |r| r[:numdocumento] == "NF001" }
    assert_equal "Entrada PIX", r[:historico]
    assert_equal "E",           r[:tp]
  end

  test "erp xlsx ignora linha sem data" do
    registros = reader("erp_test.xlsx", ERP_CONFIG).registros_erp
    refute registros.any? { |r| r[:numdocumento] == "NF004" }
  end

  # ── read_headers ─────────────────────────────────────────────────────────────

  test "read_headers retorna cabecalhos do banco xlsx" do
    headers = PlanilhaReader.read_headers(fixture("banco_test.xlsx"), 1)
    assert_includes headers, "Data"
    assert_includes headers, "Valor (R$)"
    assert_includes headers, "Descrição"
    assert_includes headers, "Documento"
  end

  test "read_headers retorna cabecalhos do banco xls" do
    headers = PlanilhaReader.read_headers(fixture("banco_test.xls"), 1)
    assert_includes headers, "Data"
    assert_includes headers, "Valor (R$)"
  end

  test "read_headers retorna array vazio para arquivo invalido" do
    headers = PlanilhaReader.read_headers("/tmp/nao_existe.xlsx", 1)
    assert_equal [], headers
  end

  # ── coluna ausente ───────────────────────────────────────────────────────────

  test "levanta ArgumentError para coluna inexistente" do
    config_errada = BANCO_CONFIG.merge(date_col: "ColunaNaoExiste")
    assert_raises(ArgumentError) do
      reader("banco_test.xlsx", config_errada).registros_banco
    end
  end

  private

  def fixture(name) = file_fixture(name).to_s
  def reader(name, config) = PlanilhaReader.new(fixture(name), config)
end
