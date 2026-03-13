class ConciliacaoService
  TOLERANCIA = 0.01

  def initialize(banco, erp)
    @banco = banco
    @erp   = erp
  end

  # Retorna Hash com:
  #   conciliados:    [{banco: {...}, erp: {...}}, ...]
  #   banco_sem_par:  [{...}, ...]
  #   erp_sem_par:    [{...}, ...]
  #   stats:          Hash
  def executar
    banco_disponivel = @banco.map { |r| r.merge(conciliado: false) }
    erp_disponivel   = @erp.map   { |r| r.merge(conciliado: false) }

    conciliados = []
    erp_por_data = erp_disponivel.group_by { |r| r[:data] }

    banco_disponivel.each do |rb|
      candidatos = erp_por_data[rb[:data]]
      next unless candidatos

      candidato = candidatos.find do |re|
        !re[:conciliado] && (re[:valor_liquido] - rb[:valor]).abs <= TOLERANCIA
      end

      next unless candidato

      candidato[:conciliado] = true
      rb[:conciliado] = true
      conciliados << { banco: rb, erp: candidato }
    end

    banco_sem_par = banco_disponivel.reject { |r| r[:conciliado] }.each { |r| r.delete(:conciliado) }
    erp_sem_par   = erp_disponivel.reject   { |r| r[:conciliado] }.each { |r| r.delete(:conciliado) }

    total_banco = @banco.size
    {
      conciliados:   conciliados,
      banco_sem_par: banco_sem_par,
      erp_sem_par:   erp_sem_par,
      stats: {
        total_banco:            total_banco,
        total_erp:              @erp.size,
        conciliados:            conciliados.size,
        banco_sem_par:          banco_sem_par.size,
        erp_sem_par:            erp_sem_par.size,
        taxa_conciliacao_banco: total_banco > 0 ? (conciliados.size.to_f / total_banco * 100).round(1) : 0
      }
    }
  end
end
