class ConciliacaoDiariaService
  TOLERANCIA_DIARIA = 0.05

  def initialize(banco_pendente, erp_pendente)
    @banco = banco_pendente
    @erp   = erp_pendente
  end

  # Retorna Hash com:
  #   dias_conciliados: [{data:, banco: [...], erp: [...], total_banco:, total_erp:}, ...]
  #   banco_sem_par:    [{...}, ...]
  #   erp_sem_par:      [{...}, ...]
  #   stats:            Hash
  def executar
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    banco_por_data = agrupar_por_data(@banco)
    erp_por_data   = agrupar_por_data(@erp)

    dias_conciliados = []
    banco_conciliado_ids = Set.new
    erp_conciliado_ids   = Set.new

    todas_datas = (banco_por_data.keys + erp_por_data.keys).uniq.sort

    todas_datas.each do |data|
      registros_banco = banco_por_data[data] || []
      registros_erp   = erp_por_data[data]   || []

      next if registros_banco.empty? || registros_erp.empty?

      total_banco = registros_banco.sum { |r| r[:valor] }
      total_erp   = registros_erp.sum   { |r| r[:valor_liquido] }

      next unless (total_banco - total_erp).abs <= TOLERANCIA_DIARIA

      dias_conciliados << {
        data:         data,
        banco:        registros_banco,
        erp:          registros_erp,
        total_banco:  total_banco.round(2),
        total_erp:    total_erp.round(2)
      }

      banco_conciliado_ids.merge(registros_banco.map { |r| r[:id] })
      erp_conciliado_ids.merge(registros_erp.map   { |r| r[:id] })
    end

    banco_sem_par = @banco.reject { |r| banco_conciliado_ids.include?(r[:id]) }
    erp_sem_par   = @erp.reject   { |r| erp_conciliado_ids.include?(r[:id]) }

    registros_banco_conciliados = dias_conciliados.sum { |d| d[:banco].size }
    registros_erp_conciliados   = dias_conciliados.sum { |d| d[:erp].size }

    Rails.logger.info({ event: "conciliacao.alg2_diario",
                        banco_in: @banco.size, erp_in: @erp.size,
                        dias_conciliados: dias_conciliados.size,
                        banco_conciliados: registros_banco_conciliados,
                        erp_conciliados: registros_erp_conciliados,
                        banco_sem_par: banco_sem_par.size, erp_sem_par: erp_sem_par.size,
                        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round }.to_json)

    {
      dias_conciliados:           dias_conciliados,
      banco_sem_par:              banco_sem_par,
      erp_sem_par:                erp_sem_par,
      stats: {
        banco_entrada:            @banco.size,
        erp_entrada:              @erp.size,
        dias_conciliados:         dias_conciliados.size,
        banco_conciliados:        registros_banco_conciliados,
        erp_conciliados:          registros_erp_conciliados,
        banco_sem_par:            banco_sem_par.size,
        erp_sem_par:              erp_sem_par.size
      }
    }
  end

  private

  def agrupar_por_data(registros)
    registros.group_by { |r| r[:data] }
  end
end
