require "test_helper"

class ConciliacaoCombinacaoServiceTest < ActiveSupport::TestCase
  # Tolerância do Alg3: ±0.01 sobre a soma da combinação
  TOL      = ConciliacaoCombinacaoService::TOLERANCIA
  MAX_DIA  = ConciliacaoCombinacaoService::MAX_POR_DIA

  D1 = Date.new(2025, 1, 10)
  D2 = Date.new(2025, 1, 11)

  # --- helpers ---

  def banco(valor, data: D1)
    { data: data, valor: valor }
  end

  def erp(valor_liquido, data: D1)
    { data: data, valor_liquido: valor_liquido }
  end

  def executar(banco_list, erp_list)
    ConciliacaoCombinacaoService.new(banco_list, erp_list).executar
  end

  # --- caso base ---

  test "banco vazio retorna zero conciliados" do
    r = executar([], [erp(100)])
    assert_equal 0, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 1, r[:erp_sem_par].size
  end

  test "erp vazio retorna zero conciliados" do
    r = executar([banco(100)], [])
    assert_equal 0, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  test "ambos vazios retorna tudo zero" do
    r = executar([], [])
    assert_equal 0, r[:conciliados].size
  end

  # --- combinações 1:N ---

  test "match 1_banco para 2_erp" do
    # 1 banco=100 casa com soma de 2 erp (60+40=100)
    r = executar([banco(100.00)], [erp(60.00), erp(40.00)])
    assert_equal 1,       r[:conciliados].size
    assert_equal "1B:2E", r[:conciliados].first[:tipo]
    assert_equal 1,       r[:conciliados].first[:banco].size
    assert_equal 2,       r[:conciliados].first[:erp].size
    assert_equal 0,       r[:banco_sem_par].size
    assert_equal 0,       r[:erp_sem_par].size
  end

  test "match 1_banco para 3_erp" do
    # 1 banco=100 casa com soma de 3 erp (40+35+25=100)
    r = executar([banco(100.00)], [erp(40.00), erp(35.00), erp(25.00)])
    assert_equal 1,       r[:conciliados].size
    assert_equal "1B:3E", r[:conciliados].first[:tipo]
    assert_equal 0,       r[:banco_sem_par].size
    assert_equal 0,       r[:erp_sem_par].size
  end

  # --- combinações N:1 ---

  test "match 2_banco para 1_erp" do
    # soma de 2 banco (60+40=100) casa com 1 erp=100
    r = executar([banco(60.00), banco(40.00)], [erp(100.00)])
    assert_equal 1,       r[:conciliados].size
    assert_equal "2B:1E", r[:conciliados].first[:tipo]
    assert_equal 2,       r[:conciliados].first[:banco].size
    assert_equal 1,       r[:conciliados].first[:erp].size
    assert_equal 0,       r[:banco_sem_par].size
    assert_equal 0,       r[:erp_sem_par].size
  end

  test "match 3_banco para 1_erp" do
    # soma de 3 banco (40+35+25=100) casa com 1 erp=100
    r = executar([banco(40.00), banco(35.00), banco(25.00)], [erp(100.00)])
    assert_equal 1,       r[:conciliados].size
    assert_equal "3B:1E", r[:conciliados].first[:tipo]
    assert_equal 0,       r[:banco_sem_par].size
    assert_equal 0,       r[:erp_sem_par].size
  end

  # --- nenhum match ---

  test "nenhum match quando valores nao formam combinacao valida" do
    # banco=100, erp=[33, 33, 33] → soma=99, diff=1 >> 0.01
    r = executar([banco(100.00)], [erp(33.00), erp(33.00), erp(33.00)])
    assert_equal 0, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 3, r[:erp_sem_par].size
  end

  test "nenhum match quando datas sao diferentes" do
    # banco no D1, erp no D2 — mesmo que valores combinem, datas incompatíveis
    r = executar([banco(100.00, data: D1)], [erp(60.00, data: D2), erp(40.00, data: D2)])
    assert_equal 0, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 2, r[:erp_sem_par].size
  end

  # --- tolerância ---

  test "concilia quando soma da combinacao difere do alvo exatamente pela tolerancia" do
    # banco=100, erp=[50.00, 50.01] → soma=100.01, diff=0.01 = TOL → casa
    r = executar([banco(100.00)], [erp(50.00), erp(50.01)])
    assert_equal 1, r[:conciliados].size
  end

  test "nao concilia quando soma da combinacao excede tolerancia" do
    # banco=100, erp=[50.00, 50.02] → soma=100.02, diff=0.02 > 0.01 → não casa
    r = executar([banco(100.00)], [erp(50.00), erp(50.02)])
    assert_equal 0, r[:conciliados].size
  end

  # --- limite MAX_POR_DIA ---

  test "dia com mais de MAX_POR_DIA registros banco e ignorado" do
    # MAX_POR_DIA+1 banco, 1 erp com total idêntico → deve ser pulado
    valor_unitario = 1.00
    total = (MAX_DIA + 1) * valor_unitario
    banco_list = Array.new(MAX_DIA + 1) { banco(valor_unitario) }
    erp_list   = [erp(total)]
    r = executar(banco_list, erp_list)
    assert_equal 0,            r[:conciliados].size
    assert_equal MAX_DIA + 1,  r[:banco_sem_par].size
    assert_equal 1,            r[:erp_sem_par].size
  end

  test "dia com mais de MAX_POR_DIA registros erp e ignorado" do
    valor_unitario = 1.00
    total = (MAX_DIA + 1) * valor_unitario
    erp_list   = Array.new(MAX_DIA + 1) { erp(valor_unitario) }
    banco_list = [banco(total)]
    r = executar(banco_list, erp_list)
    assert_equal 0,            r[:conciliados].size
    assert_equal 1,            r[:banco_sem_par].size
    assert_equal MAX_DIA + 1,  r[:erp_sem_par].size
  end

  # --- múltiplos matches no mesmo dia ---

  test "encontra multiplos grupos de combinacao no mesmo dia sequencialmente" do
    # banco=[100, 200], erp=[60, 40, 120, 80]
    # Match1: banco[0]=100 → erp [60+40=100] "1B:2E"
    # Match2: banco[1]=200 → erp [120+80=200] "1B:2E"
    banco_list = [banco(100.00), banco(200.00)]
    erp_list   = [erp(60.00), erp(40.00), erp(120.00), erp(80.00)]
    r = executar(banco_list, erp_list)
    assert_equal 2, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
    assert r[:conciliados].all? { |c| c[:tipo] == "1B:2E" }
  end

  test "registros de dias distintos sao conciliados de forma independente" do
    # D1: banco[50]+banco[50] → erp[100]; D2: banco[200] → erp[120]+erp[80]
    banco_list = [banco(50.00, data: D1), banco(50.00, data: D1), banco(200.00, data: D2)]
    erp_list   = [erp(100.00, data: D1), erp(120.00, data: D2), erp(80.00, data: D2)]
    r = executar(banco_list, erp_list)
    assert_equal 2, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
    tipos = r[:conciliados].map { |c| c[:tipo] }.sort
    assert_equal ["1B:2E", "2B:1E"], tipos
  end

  # --- stats ---

  test "stats refletem grupos e registros conciliados corretamente" do
    # 1 grupo "2B:1E": 2 banco para 1 erp
    banco_list = [banco(60.00), banco(40.00)]
    erp_list   = [erp(100.00)]
    r = executar(banco_list, erp_list)
    s = r[:stats]
    assert_equal 2, s[:banco_entrada]
    assert_equal 1, s[:erp_entrada]
    assert_equal 1, s[:grupos_conciliados]
    assert_equal 2, s[:banco_conciliados]
    assert_equal 1, s[:erp_conciliados]
    assert_equal 0, s[:banco_sem_par]
    assert_equal 0, s[:erp_sem_par]
  end
end
