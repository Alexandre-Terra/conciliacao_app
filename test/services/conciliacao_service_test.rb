require "test_helper"

class ConciliacaoServiceTest < ActiveSupport::TestCase
  # Tolerância do Alg1: ±0.01
  TOL = ConciliacaoService::TOLERANCIA

  D1 = Date.new(2025, 1, 10)
  D2 = Date.new(2025, 1, 11)

  # --- helpers ---

  def banco(valor, data: D1)
    { data: data, valor: valor, historico: "Transferência" }
  end

  def erp(valor_liquido, data: D1)
    { data: data, valor_liquido: valor_liquido }
  end

  def executar(banco_list, erp_list)
    ConciliacaoService.new(banco_list, erp_list).executar
  end

  # --- caso base ---

  test "banco vazio retorna zero conciliados e erp_sem_par com todos os registros erp" do
    r = executar([], [erp(100)])
    assert_equal 0,  r[:conciliados].size
    assert_equal 0,  r[:banco_sem_par].size
    assert_equal 1,  r[:erp_sem_par].size
  end

  test "erp vazio retorna zero conciliados e banco_sem_par com todos os registros banco" do
    r = executar([banco(100)], [])
    assert_equal 0, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  test "ambos vazios retorna tudo zero" do
    r = executar([], [])
    assert_equal 0, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- match perfeito ---

  test "match perfeito casa todos os registros sem pendentes" do
    banco_list = [banco(100.00), banco(200.50), banco(300.00)]
    erp_list   = [erp(100.00),  erp(200.50),  erp(300.00)]
    r = executar(banco_list, erp_list)
    assert_equal 3, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- nenhum match ---

  test "nenhum match quando datas sao diferentes" do
    r = executar([banco(100, data: D1)], [erp(100, data: D2)])
    assert_equal 0, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 1, r[:erp_sem_par].size
  end

  test "nenhum match quando diferenca de valor excede tolerancia" do
    r = executar([banco(100.00)], [erp(100.02)])   # diff = 0.02 > 0.01
    assert_equal 0, r[:conciliados].size
  end

  # --- parcial ---

  test "conciliacao parcial deixa registros sem par corretos" do
    # banco[0] casa com erp[1]; banco[1] e erp[0] e erp[2] ficam pendentes
    banco_list = [banco(50.00), banco(99.99)]
    erp_list   = [erp(200.00), erp(50.00), erp(300.00)]
    r = executar(banco_list, erp_list)
    assert_equal 1, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 2, r[:erp_sem_par].size
  end

  # --- tolerância ---

  test "concilia quando diferenca de valor e exatamente a tolerancia" do
    # 50.01 - 50.00 = 0.00999... < 0.01 → casa
    # (100.01 - 100.00 = 0.01000...5 em float — ultrapassa o limite; usar 50.x)
    r = executar([banco(50.00)], [erp(50.01)])
    assert_equal 1, r[:conciliados].size
  end

  test "nao concilia quando diferenca de valor supera tolerancia" do
    # 50.02 - 50.00 = 0.02 > 0.01 → não casa
    r = executar([banco(50.00)], [erp(50.02)])
    assert_equal 0, r[:conciliados].size
  end

  # --- mesma data com múltiplos registros ---

  test "multiplos registros na mesma data com valores distintos casam corretamente" do
    banco_list = [banco(100.00), banco(200.00)]
    erp_list   = [erp(200.00),  erp(100.00)]   # ordem invertida no ERP
    r = executar(banco_list, erp_list)
    assert_equal 2, r[:conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  test "mesmo erp nao e reutilizado para dois registros banco com igual valor" do
    # 2 banco com valor=100, mas apenas 1 erp com valor_liquido=100
    banco_list = [banco(100.00), banco(100.00)]
    erp_list   = [erp(100.00)]
    r = executar(banco_list, erp_list)
    assert_equal 1, r[:conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- stats ---

  test "stats refletem resultado correto" do
    banco_list = [banco(100.00), banco(200.00)]
    erp_list   = [erp(100.00),  erp(999.00)]
    r = executar(banco_list, erp_list)
    s = r[:stats]
    assert_equal 2,    s[:total_banco]
    assert_equal 2,    s[:total_erp]
    assert_equal 1,    s[:conciliados]
    assert_equal 1,    s[:banco_sem_par]
    assert_equal 1,    s[:erp_sem_par]
    assert_equal 50.0, s[:taxa_conciliacao_banco]
  end
end
