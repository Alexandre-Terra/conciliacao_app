class PlanilhaReader
  # config keys esperados:
  #   header_row: Integer (1-based linha do cabeçalho, 0 = sem cabeçalho fixo)
  #   date_col:   String (nome da coluna de data)
  #   value_col:  String (nome da coluna de valor — banco)
  #   valcred_col / valdeb_col — para ERP
  #   desc_col:   String (nome da coluna de descrição)
  #   doc_col:    String (opcional)
  #   tp_col:     String (opcional, para ERP)

  def initialize(path, config)
    @path   = path
    @config = config.transform_keys(&:to_sym)
  end

  # Retorna [cabeçalhos, [[row_values], ...]] apenas com as linhas de dados
  def headers_and_rows
    sheet = open_sheet
    header_row_index = @config[:header_row].to_i  # 1-based
    headers = sheet.row(header_row_index).map { |h| h.to_s.strip }
    rows = []
    ((header_row_index + 1)..sheet.last_row).each do |r|
      rows << sheet.row(r)
    end
    [headers, rows]
  end

  # Retorna Array of Hashes com chaves normalizadas para o banco
  def registros_banco
    headers, rows = headers_and_rows
    date_idx  = col_index(headers, @config[:date_col])
    value_idx = col_index(headers, @config[:value_col])
    desc_idx  = col_index(headers, @config[:desc_col])
    doc_idx   = @config[:doc_col].present? ? col_index(headers, @config[:doc_col]) : nil

    registros = []
    rows.each_with_index do |row, i|
      data  = parse_date(row[date_idx])
      valor = to_f(row[value_idx])
      next if data.nil? || valor.nil?

      registros << {
        id:       i + 1,
        data:     data,
        valor:    valor,
        descricao: row[desc_idx].to_s.strip,
        documento: doc_idx ? row[doc_idx].to_s.strip : ""
      }
    end
    registros
  end

  # Retorna Array of Hashes com chaves normalizadas para o ERP
  def registros_erp
    headers, rows = headers_and_rows
    date_idx    = col_index(headers, @config[:date_col])
    valcred_idx = col_index(headers, @config[:valcred_col])
    valdeb_idx  = col_index(headers, @config[:valdeb_col])
    hist_idx    = col_index(headers, @config[:desc_col])
    doc_idx     = @config[:doc_col].present? ? col_index(headers, @config[:doc_col]) : nil
    tp_idx      = @config[:tp_col].present? ? col_index(headers, @config[:tp_col]) : nil

    registros = []
    rows.each_with_index do |row, i|
      data = parse_date(row[date_idx])
      next if data.nil?

      valcred = to_f(row[valcred_idx]) || 0.0
      valdeb  = to_f(row[valdeb_idx])  || 0.0
      valor_liquido = valcred - valdeb

      registros << {
        id:            i + 1,
        data:          data,
        valor_liquido: valor_liquido,
        valcred:       valcred,
        valdeb:        valdeb,
        historico:     row[hist_idx].to_s.strip,
        numdocumento:  doc_idx ? row[doc_idx].to_s.strip : "",
        tp:            tp_idx ? row[tp_idx].to_s.strip : ""
      }
    end
    registros
  end

  # Lê só os cabeçalhos (para o passo de configuração)
  def self.read_headers(path, header_row)
    ext = File.extname(path).downcase.delete(".")
    sheet = Roo::Spreadsheet.open(path, extension: ext.to_sym)
    sheet.row(header_row.to_i).map { |h| h.to_s.strip }.reject(&:empty?)
  rescue
    []
  end

  private

  def open_sheet
    ext = File.extname(@path).downcase.delete(".")
    Roo::Spreadsheet.open(@path, extension: ext.to_sym)
  end

  def col_index(headers, col_name)
    idx = headers.index { |h| h.casecmp?(col_name.to_s) }
    raise ArgumentError, "Coluna '#{col_name}' não encontrada. Disponíveis: #{headers.join(', ')}" if idx.nil?
    idx
  end

  def parse_date(val)
    return nil if val.nil? || val.to_s.strip.empty?
    return val.to_date if val.is_a?(Date) || val.is_a?(DateTime) || val.is_a?(Time)
    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end

  def to_f(val)
    return nil if val.nil?
    Float(val.to_s.gsub(",", "."))
  rescue ArgumentError, TypeError
    nil
  end
end
