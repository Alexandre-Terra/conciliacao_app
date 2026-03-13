class RelatorioExportService
  def initialize(resultado_alg1, resultado_alg2, resultado_alg3, dir)
    @r1  = resultado_alg1
    @r2  = resultado_alg2
    @r3  = resultado_alg3
    @dir = dir
  end

  def gerar
    gerar_conciliados
    gerar_pendentes
  end

  def caminho_conciliados
    File.join(@dir, "conciliados.xlsx")
  end

  def caminho_pendentes
    File.join(@dir, "pendentes.xlsx")
  end

  private

  HEADER_COLOR = "1F6AA5"
  ALG1_COLOR   = "D9EAD3"
  ALG2_COLOR   = "D0E4F7"
  ALG3_COLOR   = "FFF2CC"
  BANCO_COLOR  = "FCE5CD"
  ERP_COLOR    = "EAD1DC"


  def gerar_conciliados
    Axlsx::Package.new do |p|
      wb = p.workbook
      styles = wb.styles
      hdr  = styles.add_style bg_color: HEADER_COLOR, fg_color: "FFFFFF", b: true
      alt1 = styles.add_style bg_color: ALG1_COLOR
      alt2 = styles.add_style bg_color: ALG2_COLOR
      alt3 = styles.add_style bg_color: ALG3_COLOR

      # ── Aba 1: Casamento Exato ──
      wb.add_worksheet(name: "Exato (Data + Valor)") do |sheet|
        sheet.add_row(
          ["ID Banco", "Data", "Descrição Banco", "Documento Banco", "Valor Banco",
           "ID ERP", "Histórico ERP", "Documento ERP", "ValCred", "ValDeb", "Valor Líquido ERP", "TP"],
          style: hdr
        )
        @r1[:conciliados].each_with_index do |par, i|
          b = par[:banco]; e = par[:erp]
          sheet.add_row(
            [b[:id], fmt_date(b[:data]), b[:descricao], b[:documento], b[:valor],
             e[:id], e[:historico], e[:numdocumento], e[:valcred], e[:valdeb], e[:valor_liquido], e[:tp]],
            style: (i.even? ? alt1 : nil)          )
        end
        sheet.column_widths 8, 12, 38, 15, 14, 8, 30, 15, 12, 12, 14, 6
      end

      # ── Aba 2: Saldo Diário ──
      wb.add_worksheet(name: "Saldo Diário") do |sheet|
        sheet.add_row(
          ["Data", "Total Banco (dia)", "Total ERP (dia)",
           "ID Banco", "Descrição Banco", "Valor Banco",
           "ID ERP", "Histórico ERP", "Valor Líquido ERP", "TP"],
          style: hdr
        )
        @r2[:dias_conciliados].each_with_index do |dia, di|
          max_rows = [dia[:banco].size, dia[:erp].size].max
          max_rows.times do |k|
            b = dia[:banco][k]; e = dia[:erp][k]
            sheet.add_row(
              [k == 0 ? fmt_date(dia[:data]) : "", k == 0 ? dia[:total_banco] : nil, k == 0 ? dia[:total_erp] : nil,
               b ? b[:id] : nil, b ? b[:descricao] : "", b ? b[:valor] : nil,
               e ? e[:id] : nil, e ? e[:historico] : "", e ? e[:valor_liquido] : nil, e ? e[:tp] : ""],
              style: (di.even? ? alt2 : nil)            )
          end
        end
        sheet.column_widths 12, 16, 16, 8, 36, 14, 8, 30, 14, 6
      end

      # ── Aba 3: Combinação (2–6) ──
      # Layout: uma linha por registro banco/erp dentro do grupo.
      # Colunas: Grupo | Tipo | Total | Lado | Seq | ID | Data | Descrição/Histórico | Valor | TP
      wb.add_worksheet(name: "Combinacao (2 a 6)") do |sheet|
        sheet.add_row(
          ["Grupo", "Tipo", "Total", "Lado", "Seq", "ID", "Data", "Descricao / Historico", "Valor", "TP"],
          style: hdr
        )
        @r3[:conciliados].each_with_index do |grupo, gi|
          style = gi.even? ? alt3 : nil
          max_rows = [grupo[:banco].size, grupo[:erp].size].max
          max_rows.times do |k|
            b = grupo[:banco][k]
            e = grupo[:erp][k]

            if b
              sheet.add_row(
                [k == 0 ? gi + 1 : nil,
                 k == 0 ? grupo[:tipo] : "",
                 k == 0 ? grupo[:total] : nil,
                 "BANCO", k + 1, b[:id], fmt_date(b[:data]), b[:descricao], b[:valor], ""],
                style: style              )
            end
            if e
              sheet.add_row(
                [nil, "", nil,
                 "ERP", k + 1, e[:id], fmt_date(e[:data]), e[:historico], e[:valor_liquido], e[:tp]],
                style: style              )
            end
          end
        end
        sheet.column_widths 7, 10, 14, 7, 5, 7, 12, 42, 14, 6
      end

      p.serialize(caminho_conciliados)
    end
  end

  def gerar_pendentes
    Axlsx::Package.new do |p|
      wb = p.workbook
      styles = wb.styles
      hdr  = styles.add_style bg_color: HEADER_COLOR, fg_color: "FFFFFF", b: true
      altb = styles.add_style bg_color: BANCO_COLOR
      alte = styles.add_style bg_color: ERP_COLOR

      wb.add_worksheet(name: "Banco") do |sheet|
        sheet.add_row(["ID Banco", "Data", "Descrição", "Documento", "Valor"], style: hdr)
        @r3[:banco_sem_par].each_with_index do |r, i|
          sheet.add_row(
            [r[:id], fmt_date(r[:data]), r[:descricao], r[:documento], r[:valor]],
            style: (i.even? ? altb : nil)          )
        end
        sheet.column_widths 8, 12, 50, 15, 14
      end

      wb.add_worksheet(name: "ERP") do |sheet|
        sheet.add_row(["ID ERP", "Data", "Histórico", "Documento", "ValCred", "ValDeb", "Valor Líquido", "TP"], style: hdr)
        @r3[:erp_sem_par].each_with_index do |r, i|
          sheet.add_row(
            [r[:id], fmt_date(r[:data]), r[:historico], r[:numdocumento], r[:valcred], r[:valdeb], r[:valor_liquido], r[:tp]],
            style: (i.even? ? alte : nil)          )
        end
        sheet.column_widths 8, 12, 40, 18, 12, 12, 14, 6
      end

      p.serialize(caminho_pendentes)
    end
  end

  def fmt_date(d)
    d.is_a?(Date) ? d.strftime("%d/%m/%Y") : d.to_s
  end
end
