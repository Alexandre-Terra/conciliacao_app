#!/usr/bin/env ruby
# Gera fixtures de planilhas para os testes de PlanilhaReader.
# Uso: bundle exec ruby test/fixtures/generate_fixtures.rb

require "bundler/setup"
require "axlsx"
require "spreadsheet"
require "date"
require "fileutils"

OUTPUT = File.expand_path("files", __dir__)
FileUtils.mkdir_p(OUTPUT)

D1 = Date.new(2025, 1, 10)
D2 = Date.new(2025, 1, 11)

# ── banco_test.xlsx ──────────────────────────────────────────────────────────
# 4 linhas de dados; a última (nil date) deve ser ignorada pelo PlanilhaReader.
# Linha 3 tem valor no formato brasileiro "1234,56" (vírgula como decimal).
Axlsx::Package.new do |pkg|
  pkg.workbook.add_worksheet(name: "Extrato") do |sheet|
    sheet.add_row ["Data", "Valor (R$)", "Descrição", "Documento"]
    sheet.add_row [D1, 100.00,    "Transferência TED", "DOC001"], types: [:date, :float,  :string, :string]
    sheet.add_row [D1, "1234,56", "PIX recebido",      "DOC002"], types: [:date, :string, :string, :string]
    sheet.add_row [D2, 200.50,    "Tarifa bancária",   "DOC003"], types: [:date, :float,  :string, :string]
    sheet.add_row [nil, 50.00,    "Linha inválida",    "DOC004"]
  end
  pkg.serialize(File.join(OUTPUT, "banco_test.xlsx"))
end
puts "✓ banco_test.xlsx"

# ── erp_test.xlsx ─────────────────────────────────────────────────────────────
Axlsx::Package.new do |pkg|
  pkg.workbook.add_worksheet(name: "ERP") do |sheet|
    sheet.add_row ["DATA", "VALCRED", "VALDEB", "HISTORICO", "NUMDOCUMENTO", "TP"]
    sheet.add_row [D1, 100.00,  0.00,  "Entrada PIX",    "NF001", "E"], types: [:date, :float, :float, :string, :string, :string]
    sheet.add_row [D1,   0.00, 50.00,  "Débito TED",     "NF002", "D"], types: [:date, :float, :float, :string, :string, :string]
    sheet.add_row [D2, 200.50,  0.00,  "Receita",        "NF003", "E"], types: [:date, :float, :float, :string, :string, :string]
    sheet.add_row [nil, 100.00,  0.00, "Linha inválida", "NF004", "E"]
  end
  pkg.serialize(File.join(OUTPUT, "erp_test.xlsx"))
end
puts "✓ erp_test.xlsx"

# ── banco_test.xls ────────────────────────────────────────────────────────────
# Usa strings ISO para datas — PlanilhaReader converte via Date.parse.
book = Spreadsheet::Workbook.new
sheet = book.create_worksheet name: "Extrato"
sheet.row(0).replace ["Data", "Valor (R$)", "Descrição", "Documento"]
sheet.row(1).replace ["2025-01-10", 100.00,    "Transferência TED", "DOC001"]
sheet.row(2).replace ["2025-01-10", "1234,56", "PIX recebido",      "DOC002"]
sheet.row(3).replace ["2025-01-11", 200.50,    "Tarifa bancária",   "DOC003"]
sheet.row(4).replace [nil,          50.00,     "Linha inválida",    "DOC004"]
book.write(File.join(OUTPUT, "banco_test.xls"))
puts "✓ banco_test.xls"

# ── erp_test.xls ──────────────────────────────────────────────────────────────
book = Spreadsheet::Workbook.new
sheet = book.create_worksheet name: "ERP"
sheet.row(0).replace ["DATA", "VALCRED", "VALDEB", "HISTORICO", "NUMDOCUMENTO", "TP"]
sheet.row(1).replace ["2025-01-10", 100.00,  0.00, "Entrada PIX",    "NF001", "E"]
sheet.row(2).replace ["2025-01-10",   0.00, 50.00, "Débito TED",     "NF002", "D"]
sheet.row(3).replace ["2025-01-11", 200.50,  0.00, "Receita",        "NF003", "E"]
sheet.row(4).replace [nil,          100.00,  0.00, "Linha inválida", "NF004", "E"]
book.write(File.join(OUTPUT, "erp_test.xls"))
puts "✓ erp_test.xls"

puts "\nDone! Files in #{OUTPUT}"
