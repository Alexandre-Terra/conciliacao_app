class ConciliacaoCombinacaoService
  TOLERANCIA      = 0.01
  TAMANHOS_COMBO  = (2..6).freeze
  MAX_POR_DIA     = 30

  def initialize(banco_pendente, erp_pendente)
    @banco = banco_pendente
    @erp   = erp_pendente
  end

  def executar
    conciliados = []
    banco_por_data = @banco.group_by { |r| r[:data] }
    erp_por_data   = @erp.group_by   { |r| r[:data] }

    todas_datas = (banco_por_data.keys + erp_por_data.keys).uniq.sort

    todas_datas.each do |data|
      banco_dia = banco_por_data[data]
      erp_dia   = erp_por_data[data]
      next unless banco_dia && erp_dia
      next if banco_dia.size > MAX_POR_DIA || erp_dia.size > MAX_POR_DIA

      loop do
        break if banco_dia.empty? || erp_dia.empty?

        match = buscar_match(banco_dia, erp_dia)
        break unless match

        conciliados << match
        match[:banco].each { |b| banco_dia.delete(b) }
        match[:erp].each   { |e| erp_dia.delete(e) }
      end
    end

    banco_sem_par = banco_por_data.values.flatten
    erp_sem_par   = erp_por_data.values.flatten
    banco_conciliados = conciliados.sum { |c| c[:banco].size }
    erp_conciliados   = conciliados.sum { |c| c[:erp].size }

    {
      conciliados:   conciliados,
      banco_sem_par: banco_sem_par,
      erp_sem_par:   erp_sem_par,
      stats: {
        banco_entrada:      @banco.size,
        erp_entrada:        @erp.size,
        grupos_conciliados: conciliados.size,
        banco_conciliados:  banco_conciliados,
        erp_conciliados:    erp_conciliados,
        banco_sem_par:      banco_sem_par.size,
        erp_sem_par:        erp_sem_par.size
      }
    }
  end

  private

  # Tenta casar 1 banco → N ERP e N banco → 1 ERP, para N = 2..6, em ordem crescente
  def buscar_match(banco_dia, erp_dia)
    TAMANHOS_COMBO.each do |n|
      # 1 banco → N ERP
      banco_dia.each do |b|
        combo = encontrar_combo(erp_dia, b[:valor], n)
        next unless combo
        return { tipo: "1B:#{n}E", banco: [b], erp: combo, total: b[:valor].round(2) }
      end

      # N banco → 1 ERP
      erp_dia.each do |e|
        combo = encontrar_combo(banco_dia, e[:valor_liquido], n)
        next unless combo
        return { tipo: "#{n}B:1E", banco: combo, erp: [e], total: e[:valor_liquido].round(2) }
      end
    end

    nil
  end

  # Procura uma combinação de `tamanho` registros em `lista` cuja soma ≈ `alvo`
  def encontrar_combo(lista, alvo, tamanho)
    return nil if lista.size < tamanho

    lista.combination(tamanho).find do |combo|
      soma = combo.sum { |r| r[:valor] || r[:valor_liquido] }
      (soma - alvo).abs <= TOLERANCIA
    end
  end
end
