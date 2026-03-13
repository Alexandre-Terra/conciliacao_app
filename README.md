# Conciliação Bancária (Rails)

Aplicação web para conciliar lançamentos de **extrato bancário** com **movimentações de ERP**, usando um pipeline de 3 algoritmos progressivos e exportação de resultados em Excel.

## Visão geral

O sistema recebe duas planilhas (`.xls` ou `.xlsx`):

- Extrato do banco
- Lançamentos do ERP

Após o upload, você configura a linha de cabeçalho e o nome das colunas de cada arquivo. Em seguida, o app executa:

1. Casamento exato por data + valor
2. Conciliação por saldo diário
3. Conciliação por combinações (1:N e N:1)

No fim, o sistema gera dois arquivos:

- `conciliados.xlsx` (3 abas)
- `pendentes.xlsx` (2 abas)

## Principais funcionalidades

- Upload de 2 arquivos via interface web
- Configuração flexível de colunas por layout
- Leitura de `.xls` e `.xlsx`
- Pipeline de conciliação em múltiplas etapas
- Estatísticas por algoritmo
- Exportação com formatação para análise operacional

## Arquitetura

### Camadas principais

- Controller: coordena fluxo de upload, configuração, processamento e download
- Reader: normaliza planilhas em estruturas Ruby
- Services de conciliação: aplicam as regras de matching
- Service de exportação: gera os arquivos `.xlsx` finais

### Fluxo HTTP

- `GET /` → tela inicial
- `POST /upload` → recebe planilhas e salva em `tmp/conciliacao/<uuid>`
- `GET /configurar` → exibe parâmetros de leitura de colunas
- `POST /processar` → executa pipeline e gera relatórios
- `GET /download/:uuid/:tipo` → baixa `conciliados.xlsx` ou `pendentes.xlsx`

## Regras de conciliação

### Algoritmo 1: Casamento Exato

- Critério: mesma data e `|valor_erp - valor_banco| <= 0.01`
- Entrada: todos os registros banco + ERP
- Saída: pares conciliados e pendências remanescentes

### Algoritmo 2: Saldo Diário

- Critério: para um mesmo dia, `|soma_banco - soma_erp| <= 0.05`
- Entrada: pendentes do Algoritmo 1
- Saída: dias conciliados (com todos os registros do dia) e novos pendentes

### Algoritmo 3: Combinação

- Critério: combinações no mesmo dia com tolerância de `0.01`
- Tipos de match:
  - `1 banco -> N ERP` (N de 2 a 6)
  - `N banco -> 1 ERP` (N de 2 a 6)
- Limite de performance por dia: até 30 registros por lado
- Entrada: pendentes do Algoritmo 2
- Saída: grupos conciliados + pendências finais

## Estrutura esperada dos dados

### Banco (normalizado)

- `data`
- `valor`
- `descricao`
- `documento` (opcional)

### ERP (normalizado)

- `data`
- `valcred`
- `valdeb`
- `valor_liquido = valcred - valdeb`
- `historico`
- `numdocumento` (opcional)
- `tp` (opcional)

## Saídas geradas

### `conciliados.xlsx`

- Aba `Exato (Data + Valor)`
- Aba `Saldo Diário`
- Aba `Combinacao (2 a 6)`

### `pendentes.xlsx`

- Aba `Banco`
- Aba `ERP`

## Stack técnica

- Ruby `4.0.1` (conforme `.ruby-version`)
- Rails `8.1.x`
- Puma
- Roo + Roo-XLS (leitura de planilhas)
- Caxlsx (geração de Excel)
- Importmap

## Requisitos

- Ruby `4.0.1`
- Bundler
- Dependências nativas para gems de planilha (ambiente Linux/macOS)

## Como rodar localmente

```bash
bundle install
bin/rails server
```

Aplicação disponível em `http://localhost:3000`.

Alternativa com script de setup:

```bash
bin/setup
```

## Como usar

1. Acesse `http://localhost:3000`
2. Envie os dois arquivos (`banco` e `erp`)
3. Ajuste linha de cabeçalho e nomes das colunas
4. Clique em **Conciliar**
5. Baixe os relatórios gerados

## Qualidade e segurança

O projeto já inclui pipeline de CI com:

- `brakeman` (segurança Rails)
- `bundler-audit` (vulnerabilidades de gems)
- `importmap audit` (dependências JS)
- `rubocop` (padronização de código)

## Observações importantes

- O app **não usa banco de dados** (sem Active Record)
- Os arquivos sobem para diretório temporário `tmp/conciliacao/<uuid>`
- Sessão expirada exige novo upload
- Colunas são localizadas por nome (case-insensitive)

## Estrutura de pastas relevante

```text
app/controllers/conciliacoes_controller.rb
app/services/planilha_reader.rb
app/services/conciliacao_service.rb
app/services/conciliacao_diaria_service.rb
app/services/conciliacao_combinacao_service.rb
app/services/relatorio_export_service.rb
app/views/conciliacoes/
```

## Melhorias futuras sugeridas

- Persistência dos resultados (histórico de execuções)
- Upload assíncrono e processamento em background
- Testes automatizados para cenários de conciliação
- Normalização de descrições por regras customizáveis
- Exportação adicional em CSV

## Licença

Defina a licença do projeto (ex.: MIT) antes de uso em produção/distribuição.
