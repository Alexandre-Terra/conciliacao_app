require "test_helper"

class ConciliacaoDiariaServiceTest < ActiveSupport::TestCase
  # Tolerância do Alg2: ±0.05 sobre o total diário
  TOL = ConciliacaoDiariaService::TOLERANCIA_DIARIA

  D1 = Date.new(2025, 1, 10)
  D2 = Date.new(2025, 1, 11)

  # --- helpers ---
  # Alg2 exige :id em cada registro para rastrear quais foram conciliados.

  def banco(id, valor, data: D1)
    { id: id, data: data, valor: valor }
  end

  def erp(id, valor_liquido, data: D1)
    { id: id, data: data, valor_liquido: valor_liquido }
  end

  def executar(banco_list, erp_list)
    ConciliacaoDiariaService.new(banco_list, erp_list).executar
  end

  # --- caso base ---

  test "banco vazio retorna zero dias conciliados" do
    r = executar([], [erp(1, 100)])
    assert_equal 0, r[:dias_conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 1, r[:erp_sem_par].size
  end

  test "erp vazio retorna zero dias conciliados" do
    r = executar([banco(1, 100)], [])
    assert_equal 0, r[:dias_conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  test "ambos vazios retorna tudo zero" do
    r = executar([], [])
    assert_equal 0, r[:dias_conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- match diário ---

  test "concilia quando totais diarios sao iguais" do
    # 2 banco (60+40=100) vs 1 erp (100) → total bate exato
    banco_list = [banco(1, 60.00), banco(2, 40.00)]
    erp_list   = [erp(1, 100.00)]
    r = executar(banco_list, erp_list)
    assert_equal 1, r[:dias_conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
    dia = r[:dias_conciliados].first
    assert_equal D1,    dia[:data]
    assert_equal 100.0, dia[:total_banco]
    assert_equal 100.0, dia[:total_erp]
  end

  test "concilia com multiplos registros em ambos os lados" do
    banco_list = [banco(1, 60.00), banco(2, 40.00)]
    erp_list   = [erp(1, 50.00),  erp(2, 50.00)]
    r = executar(banco_list, erp_list)
    assert_equal 1, r[:dias_conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- tolerância ---

  test "concilia quando diferenca de totais e exatamente a tolerancia" do
    # 100.05 - 100.00 = 0.05 = TOL → casa (usa literal para evitar imprecisão float)
    r = executar([banco(1, 100.00)], [erp(1, 100.05)])
    assert_equal 1, r[:dias_conciliados].size
  end

  test "nao concilia quando diferenca de totais supera tolerancia" do
    # 100.06 - 100.00 = 0.06 > 0.05 → rejeita
    r = executar([banco(1, 100.00)], [erp(1, 100.06)])
    assert_equal 0, r[:dias_conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 1, r[:erp_sem_par].size
  end

  # --- parcial entre dias ---

  test "concilia apenas o dia cujos totais batem e mantem o outro como pendente" do
    # D1 casa: banco=100, erp=100
    # D2 nao casa: banco=50, erp=200 (diff=150 >> 0.05)
    banco_list = [banco(1, 100.00, data: D1), banco(2, 50.00, data: D2)]
    erp_list   = [erp(1, 100.00,  data: D1), erp(2, 200.00, data: D2)]
    r = executar(banco_list, erp_list)
    assert_equal 1, r[:dias_conciliados].size
    assert_equal D1, r[:dias_conciliados].first[:data]
    assert_equal 1,  r[:banco_sem_par].size
    assert_equal 1,  r[:erp_sem_par].size
    assert_equal 2,  r[:banco_sem_par].first[:id]   # banco do D2
    assert_equal 2,  r[:erp_sem_par].first[:id]     # erp do D2
  end

  test "datas diferentes nao conciliam mesmo com totais individuais iguais" do
    r = executar([banco(1, 100, data: D1)], [erp(1, 100, data: D2)])
    assert_equal 0, r[:dias_conciliados].size
    assert_equal 1, r[:banco_sem_par].size
    assert_equal 1, r[:erp_sem_par].size
  end

  test "dois dias conciliados independentemente" do
    banco_list = [banco(1, 100.00, data: D1), banco(2, 200.00, data: D2)]
    erp_list   = [erp(1, 100.00,  data: D1), erp(2, 200.00,  data: D2)]
    r = executar(banco_list, erp_list)
    assert_equal 2, r[:dias_conciliados].size
    assert_equal 0, r[:banco_sem_par].size
    assert_equal 0, r[:erp_sem_par].size
  end

  # --- stats ---

  test "stats refletem entrada e resultado corretamente" do
    banco_list = [banco(1, 60.00), banco(2, 40.00), banco(3, 99.00, data: D2)]
    erp_list   = [erp(1, 100.00),                   erp(2, 50.00,  data: D2)]
    # D1: banco=100, erp=100 → casa. D2: banco=99, erp=50 → nao casa
    r = executar(banco_list, erp_list)
    s = r[:stats]
    assert_equal 3, s[:banco_entrada]
    assert_equal 2, s[:erp_entrada]
    assert_equal 1, s[:dias_conciliados]
    assert_equal 2, s[:banco_conciliados]
    assert_equal 1, s[:erp_conciliados]
    assert_equal 1, s[:banco_sem_par]
    assert_equal 1, s[:erp_sem_par]
  end
end
