# Plano de Deploy — Conciliacao Bancaria no Render

> **Status:** Planejamento
> **Plataforma:** Render (Docker)
> **Data:** 2026-03-16

---

## Por que nao Vercel?

| Problema | Impacto |
|----------|---------|
| Ruby sem runtime oficial | Apenas community runtimes experimentais, sem suporte a Ruby 4.x |
| Filesystem efemero por invocacao | Arquivo salvo em `/upload` nao existe quando `/processar` e chamado |
| Cold start Rails ~5-15s | Consome o timeout de 10s do plano Hobby antes de processar |
| Gems com compilacao nativa (nokogiri, roo, caxlsx) | Build serverless complexo e fragil |
| Sessao com paths locais | `session[:banco_path]` aponta para path que nao existe em outra invocacao |

**Render resolve tudo isso:** processo Puma persistente, disco anexavel, TLS automatico, deploy Docker nativo, ~US$7-15/mes.

---

## Resumo das Fases

| Fase | Foco | Tickets | Pode paralelizar? |
|------|------|---------|--------------------|
| 0 | Seguranca e Validacao | 0.1 a 0.4 | Sim, todos em paralelo |
| 1 | Plataforma Render | 1.1 a 1.4 | Parcial (1.1 primeiro) |
| 2 | Robustez Operacional | 2.1 a 2.4 | Sim, todos em paralelo |
| 3 | Testes e Validacao | 3.1 a 3.5 | Paralelo com fases 0-2 |
| 4 | Evolucao Futura | 4.1 a 4.3 | Pos go-live |

```
FASE 0 (paralelo):  0.1  0.2  0.3  0.4      FASE 3 (paralelo com tudo):
                      |                        3.1  3.2  3.3
FASE 1:             1.1 -> 1.2 -> 1.3                |
                      |           1.4          3.4  3.5 (apos 1.1)
FASE 2:             2.1  2.2  2.3  2.4
```

---

## FASE 0 — Seguranca e Validacao

### TICKET 0.1 — Habilitar HTTPS (force_ssl + assume_ssl)

**Prioridade:** Alta
**Dependencias:** Nenhuma

**Descricao:**
O arquivo `config/environments/production.rb` tem `config.assume_ssl` e `config.force_ssl` comentados (linhas 25-29). Em producao, todo trafego deve ser HTTPS. O Render fornece TLS automatico, mas o Rails precisa saber que esta atras de proxy TLS.

Alem disso, o Content Security Policy em `config/initializers/content_security_policy.rb` esta totalmente comentado — deve ser ativado para prevenir XSS.

**Acoes:**
1. Descomentar `config.assume_ssl = true` em `production.rb`
2. Descomentar `config.force_ssl = true` em `production.rb`
3. Configurar `ssl_options` para excluir o healthcheck `/up` do redirect
4. Ativar CSP no initializer com politica restritiva
5. Adicionar `nonce: true` para scripts inline ou mover JS da view `configurar.html.erb` para arquivo externo via Importmap

**Arquivos:**
- `config/environments/production.rb`
- `config/initializers/content_security_policy.rb`
- `app/views/conciliacoes/configurar.html.erb` (JS inline precisa de nonce)

**Criterios de aceite:**
- [ ] `curl -I http://dominio` retorna 301 para HTTPS
- [ ] Header `Strict-Transport-Security` presente nas respostas
- [ ] Cookies marcados como `secure`
- [ ] CSP headers ativos (verificar via DevTools > Network)
- [ ] Healthcheck `/up` acessivel sem redirect loop
- [ ] JS inline da view `configurar` funciona com CSP ativo

---

### TICKET 0.2 — Validacao de upload (tipo, extensao, tamanho)

**Prioridade:** Alta
**Dependencias:** Nenhuma

**Descricao:**
O `ConciliacoesController#upload` (linhas 12-35) aceita qualquer arquivo — apenas verifica se o parametro esta presente. Nao ha validacao de extensao, content-type ou tamanho. Um usuario pode fazer upload de arquivos maliciosos ou enormes.

**Acoes:**
1. Validar extensao: apenas `.xls` e `.xlsx`
2. Validar content-type: `application/vnd.ms-excel` e `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
3. Validar tamanho maximo: 20MB por arquivo (configuravel via ENV `MAX_UPLOAD_SIZE_MB`)
4. Retornar mensagem amigavel em portugues para cada tipo de erro
5. Considerar adicionar limite no Rack level para rejeitar payloads grandes antes de buffering

**Arquivos:**
- `app/controllers/conciliacoes_controller.rb`

**Criterios de aceite:**
- [ ] Upload de `.txt` retorna flash error "Formato invalido. Apenas .xls e .xlsx sao aceitos."
- [ ] Upload de arquivo >20MB retorna flash error "Arquivo excede o tamanho maximo de 20MB."
- [ ] Upload de arquivo com content-type invalido (ex: `text/plain` renomeado para `.xlsx`) retorna erro
- [ ] Uploads validos continuam funcionando normalmente
- [ ] Limite de tamanho configuravel via variavel de ambiente

---

### TICKET 0.3 — Filtrar dados sensiveis nos logs

**Prioridade:** Media
**Dependencias:** Nenhuma

**Descricao:**
O `filter_parameter_logging.rb` filtra senhas e tokens, mas nao filtra dados financeiros. Objetos `ActionDispatch::Http::UploadedFile` podem aparecer nos logs de parametros. Para conformidade LGPD, dados bancarios nao devem aparecer em logs.

**Acoes:**
1. Adicionar `banco_file` e `erp_file` a lista de filtros (nomes dos parametros de upload)
2. Verificar se `ActionDispatch::Http::UploadedFile#inspect` expoe conteudo nos logs
3. Adicionar filtro para parametros de configuracao que possam conter nomes de colunas sensiveis

**Arquivos:**
- `config/initializers/filter_parameter_logging.rb`

**Criterios de aceite:**
- [ ] Logs de producao nao contem conteudo de arquivos uploaded
- [ ] Nomes dos arquivos aparecem (para debug) mas nao o conteudo
- [ ] Parametros de colunas (col_data, col_valor, etc.) sao logados normalmente (nao sao sensiveis)

---

### TICKET 0.4 — Host Authorization em producao

**Prioridade:** Media
**Dependencias:** Nenhuma

**Descricao:**
Em `production.rb` (linhas 57-63), `config.hosts` esta comentado. Sem isso, o app aceita requests com qualquer header `Host`, permitindo ataques de DNS rebinding.

**Acoes:**
1. Configurar `config.hosts` com dominio de producao via ENV `ALLOWED_HOSTS`
2. Permitir multiplos hosts separados por virgula no ENV
3. Excluir healthcheck `/up` da verificacao (ja e a config padrao do Rails)
4. Adicionar `.render.com` como host permitido para o dominio default do Render

**Arquivos:**
- `config/environments/production.rb`

**Criterios de aceite:**
- [ ] Request com `Host: evil.com` retorna 403
- [ ] Request com dominio real retorna 200
- [ ] Healthcheck `/up` continua acessivel
- [ ] Hosts configuraveis via ENV sem redeploy

---

## FASE 1 — Plataforma Render

### TICKET 1.1 — Criar render.yaml (Blueprint)

**Prioridade:** Critica
**Dependencias:** Ticket 0.1

**Descricao:**
Criar o Infrastructure as Code do Render para deploy automatico. O app ja tem Dockerfile funcional com multi-stage build, Puma e Thruster.

**Acoes:**
1. Criar `render.yaml` na raiz do projeto
2. Definir Web Service tipo Docker
3. Configurar variaveis de ambiente:
   - `RAILS_MASTER_KEY` (sync: false — inserir manualmente no painel)
   - `RAILS_ENV=production`
   - `RAILS_LOG_LEVEL=info`
   - `ALLOWED_HOSTS` (dominio do Render)
   - `RAILS_MAX_THREADS=3`
4. Configurar disco persistente:
   - Mount path: `/rails/tmp/conciliacao`
   - Tamanho: 1GB
5. Healthcheck: path `/up`, intervalo 30s
6. Plano: Starter ($7/mes) ou Standard ($25/mes) conforme necessidade

**Arquivos:**
- Novo `render.yaml`

**Exemplo de estrutura:**
```yaml
services:
  - type: web
    name: conciliacao-app
    runtime: docker
    plan: starter
    healthCheckPath: /up
    envVars:
      - key: RAILS_ENV
        value: production
      - key: RAILS_LOG_LEVEL
        value: info
      - key: RAILS_MASTER_KEY
        sync: false
      - key: ALLOWED_HOSTS
        value: conciliacao-app.onrender.com
      - key: RAILS_MAX_THREADS
        value: "3"
    disk:
      name: conciliacao-tmp
      mountPath: /rails/tmp/conciliacao
      sizeGB: 1
```

**Criterios de aceite:**
- [ ] `render.yaml` valido (validar com Render Blueprint spec)
- [ ] Deploy automatico funciona via push para `main`
- [ ] Disco persistente montado e gravavel pelo app
- [ ] Variaveis de ambiente acessiveis pelo Rails
- [ ] Healthcheck `/up` retorna 200

---

### TICKET 1.2 — Ajustar Dockerfile para Render

**Prioridade:** Alta
**Dependencias:** Ticket 1.1

**Descricao:**
O Dockerfile existente foi criado para Kamal e precisa de ajustes para Render. O container roda como usuario `rails` (UID 1000) e o disco persistente precisa de permissoes corretas.

**Acoes:**
1. Garantir que o diretorio `/rails/tmp/conciliacao` existe no container com permissoes para o usuario `rails`
2. Adicionar instrucao `HEALTHCHECK` ao Dockerfile
3. Verificar que o `bin/docker-entrypoint` cria o diretorio se nao existir (para primeiro boot antes do disco ser montado)
4. Testar build local: `docker build -t conciliacao-app .`
5. Testar run local: `docker run -p 3000:80 conciliacao-app`

**Arquivos:**
- `Dockerfile`
- `bin/docker-entrypoint`

**Criterios de aceite:**
- [ ] `docker build` completa sem erros
- [ ] Container inicia sem erros de permissao
- [ ] Escrita em `/rails/tmp/conciliacao/` funciona dentro do container
- [ ] `HEALTHCHECK` presente e funcional
- [ ] `bin/docker-entrypoint` cria dir se ausente

---

### TICKET 1.3 — Dominio customizado + TLS

**Prioridade:** Media
**Dependencias:** Tickets 0.1, 0.4, 1.1

**Descricao:**
Configurar dominio customizado no Render. TLS e automatico via Let's Encrypt.

**Acoes:**
1. Registrar dominio (se ainda nao tiver)
2. Adicionar dominio customizado no painel do Render
3. Configurar DNS (CNAME para `*.onrender.com`)
4. Atualizar `ALLOWED_HOSTS` com dominio final
5. Verificar TLS funcional

**Arquivos:**
- `config/environments/production.rb` (atualizar ALLOWED_HOSTS default)
- Painel Render

**Criterios de aceite:**
- [ ] App acessivel via dominio customizado com HTTPS
- [ ] Certificado TLS valido (verificar com `curl -v`)
- [ ] HTTP redireciona para HTTPS
- [ ] Certificado auto-renovavel pelo Render

---

### TICKET 1.4 — CI/CD com deploy automatico

**Prioridade:** Media
**Dependencias:** Ticket 1.1

**Descricao:**
O projeto ja tem CI via GitHub Actions (`.github/workflows/ci.yml`) com brakeman, bundler-audit, importmap audit e rubocop. Integrar com deploy automatico no Render.

**Acoes:**
1. Configurar Render para auto-deploy a partir da branch `main`
2. Configurar branch filter no Render (apenas `main` para producao)
3. Adicionar step de testes ao CI workflow (quando Fase 3 estiver completa)
4. Documentar processo de rollback via Render dashboard

**Arquivos:**
- `.github/workflows/ci.yml`
- Configuracao no painel Render

**Criterios de aceite:**
- [ ] Push para `main` dispara build no Render
- [ ] Build com erro no CI nao dispara deploy (configurar deploy hook manual se necessario)
- [ ] Rollback disponivel via Render dashboard para ultimas 5 versoes
- [ ] Processo de rollback documentado

---

## FASE 2 — Robustez Operacional

### TICKET 2.1 — Limpeza automatica de tmp por TTL

**Prioridade:** Alta
**Dependencias:** Ticket 1.1

**Descricao:**
Nao existe rotina de limpeza para `tmp/conciliacao/`. Com disco persistente no Render, os arquivos acumulam indefinidamente. Dados financeiros nao devem ser retidos alem do necessario (LGPD).

**Acoes:**
1. Criar Rake task `tmp:cleanup` em `lib/tasks/tmp_cleanup.rake`
2. A task deve:
   - Iterar diretorios em `Rails.root.join("tmp", "conciliacao")`
   - Remover diretorios com `mtime` > 2 horas
   - Logar cada remocao com UUID e timestamp
   - Nao falhar se o diretorio base nao existir
3. Adicionar cron job no `render.yaml`:
   - Tipo: `cron`
   - Schedule: `*/30 * * * *` (a cada 30 minutos)
   - Comando: `bin/rails tmp:cleanup`

**Arquivos:**
- Novo `lib/tasks/tmp_cleanup.rake`
- `render.yaml` (adicionar cron service)

**Exemplo da task:**
```ruby
namespace :tmp do
  desc "Remove temporary conciliation directories older than TTL"
  task cleanup: :environment do
    ttl = ENV.fetch("TMP_CLEANUP_TTL_HOURS", "2").to_i
    base = Rails.root.join("tmp", "conciliacao")
    next unless base.exist?

    base.children.select(&:directory?).each do |dir|
      if dir.mtime < ttl.hours.ago
        FileUtils.rm_rf(dir)
        Rails.logger.info("tmp:cleanup removed #{dir.basename} (mtime: #{dir.mtime})")
      end
    end
  end
end
```

**Criterios de aceite:**
- [ ] Diretorios com mais de 2h sao removidos
- [ ] Diretorios com menos de 2h sao preservados
- [ ] Task nao falha se `tmp/conciliacao` nao existir
- [ ] Log de cada remocao com UUID e timestamp
- [ ] TTL configuravel via ENV `TMP_CLEANUP_TTL_HOURS`
- [ ] Cron executando a cada 30 minutos no Render

---

### TICKET 2.2 — Timeout de aplicacao (Rack::Timeout)

**Prioridade:** Alta
**Dependencias:** Ticket 1.1

**Descricao:**
O processamento em `ConciliacoesController#processar` pode levar dezenas de segundos com planilhas grandes, especialmente o algoritmo combinatorio. Sem timeout explicitoa, uma request pode travar o thread do Puma indefinidamente. O Render tem timeout default de 30s.

**Acoes:**
1. Adicionar gem `rack-timeout` ao Gemfile
2. Criar `config/initializers/rack_timeout.rb` com timeout de 90s
3. Solicitar aumento de timeout no Render para 120s (via dashboard ou suporte)
4. Capturar `Rack::Timeout::RequestTimeoutException` no controller com mensagem amigavel
5. Documentar limites de tamanho de planilha na UI

**Arquivos:**
- `Gemfile`
- Novo `config/initializers/rack_timeout.rb`
- `app/controllers/conciliacoes_controller.rb` (rescue timeout)

**Criterios de aceite:**
- [ ] Rack::Timeout configurado com service_timeout 90s
- [ ] Timeout Render configurado para 120s
- [ ] Request que excede 90s mostra mensagem amigavel (nao 502 generico)
- [ ] Log do timeout inclui request_id e duracao

---

### TICKET 2.3 — Logs estruturados JSON com request_id

**Prioridade:** Media
**Dependencias:** Nenhuma

**Descricao:**
O `production.rb` ja usa `config.log_tags = [:request_id]` e loga em STDOUT, mas o formato e texto livre. Logs estruturados em JSON facilitam busca e analise no Render Log Explorer.

**Acoes:**
1. Adicionar gem `lograge` ao Gemfile
2. Criar `config/initializers/lograge.rb` com output JSON
3. Incluir campos: method, path, status, duration, request_id, controller, action
4. Adicionar logging nos services com metricas:
   - PlanilhaReader: quantidade de registros lidos
   - ConciliacaoService: registros conciliados / pendentes
   - Tempo de cada algoritmo

**Arquivos:**
- `Gemfile`
- Novo `config/initializers/lograge.rb`
- `config/environments/production.rb`

**Exemplo de configuracao Lograge:**
```ruby
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_payload do |controller|
    { request_id: controller.request.request_id }
  end
end
```

**Criterios de aceite:**
- [ ] Cada request gera uma linha JSON com method, path, status, duration, request_id
- [ ] Logs renderizam corretamente no Render Log Explorer
- [ ] Services logam quantidade de registros processados
- [ ] Erros incluem backtrace no log

---

### TICKET 2.4 — Politica LGPD para dados financeiros

**Prioridade:** Alta
**Dependencias:** Tickets 0.3, 2.1

**Descricao:**
O app processa extratos bancarios e lancamentos ERP — dados financeiros sensiveis sob a LGPD. E necessario definir base legal, politica de retencao e informar o usuario.

**Acoes:**
1. Adicionar aviso de privacidade na tela de upload (`new.html.erb`)
2. Informar que:
   - Arquivos sao processados no servidor e removidos automaticamente apos 2h
   - Nenhum dado e armazenado permanentemente
   - Nenhum dado e compartilhado com terceiros
3. Criar pagina de politica de privacidade simples
4. Garantir que logs nao contem dados financeiros (validar Ticket 0.3)

**Arquivos:**
- `app/views/conciliacoes/new.html.erb`
- Novo `app/views/conciliacoes/privacidade.html.erb` (ou `public/privacidade.html`)
- `config/routes.rb` (rota para politica)

**Criterios de aceite:**
- [ ] Aviso de privacidade visivel na tela de upload antes do botao de envio
- [ ] Link para politica de privacidade completa
- [ ] Politica documenta: dados coletados, finalidade, retencao (2h), base legal
- [ ] Logs confirmados sem dados financeiros

---

## FASE 3 — Testes e Validacao

> Pode ser executada em paralelo com as Fases 0, 1 e 2.

### TICKET 3.1 — Testes unitarios dos 3 algoritmos de conciliacao

**Prioridade:** Critica
**Dependencias:** Nenhuma

**Descricao:**
O projeto NAO tem nenhum teste automatizado. O CI roda apenas linters e scanners. Qualquer mudanca nos services pode quebrar a conciliacao silenciosamente. Este e o maior risco tecnico do projeto.

**Acoes:**
1. Criar `test/services/conciliacao_service_test.rb`
2. Criar `test/services/conciliacao_diaria_service_test.rb`
3. Criar `test/services/conciliacao_combinacao_service_test.rb`
4. Casos de teste para cada algoritmo:
   - **Caso base:** 0 registros em um lado ou ambos
   - **Match perfeito:** todos os registros conciliam
   - **Nenhum match:** nenhum registro concilia
   - **Parcial:** alguns conciliam, alguns ficam pendentes
   - **Tolerancia:** valores dentro e fora da tolerancia (0.01 para alg1/alg3, 0.05 para alg2)
   - **Datas:** mesmo dia com multiplos registros, datas diferentes
   - **Combinacoes (alg3):** 1:2, 1:3, 2:1, 3:1, e limite MAX_POR_DIA
5. Usar dados sinteticos (hashes com :data, :valor, :historico)

**Arquivos:**
- Novo `test/services/conciliacao_service_test.rb`
- Novo `test/services/conciliacao_diaria_service_test.rb`
- Novo `test/services/conciliacao_combinacao_service_test.rb`

**Criterios de aceite:**
- [ ] Testes dos 3 services passando
- [ ] Cobertura de todos os cenarios listados acima
- [ ] Suite roda em < 10s
- [ ] Adicionado ao CI workflow

---

### TICKET 3.2 — Testes do PlanilhaReader e RelatorioExportService

**Prioridade:** Alta
**Dependencias:** Nenhuma

**Descricao:**
Testar leitura de planilhas `.xls` e `.xlsx` e geracao de relatorios Excel.

**Acoes:**
1. Criar fixtures: arquivos `.xls` e `.xlsx` com dados de teste em `test/fixtures/files/`
2. Criar `test/services/planilha_reader_test.rb`:
   - Leitura de .xls e .xlsx
   - Deteccao correta de headers
   - Normalizacao de datas e valores
   - Tratamento de valores com virgula (locale brasileiro)
3. Criar `test/services/relatorio_export_service_test.rb`:
   - Geracao de `conciliados.xlsx` com 3 sheets
   - Geracao de `pendentes.xlsx` com 2 sheets
   - Arquivo gerado e .xlsx valido

**Arquivos:**
- Novos fixtures em `test/fixtures/files/`
- Novo `test/services/planilha_reader_test.rb`
- Novo `test/services/relatorio_export_service_test.rb`

**Criterios de aceite:**
- [ ] Fixtures .xls e .xlsx presentes
- [ ] PlanilhaReader le ambos os formatos corretamente
- [ ] Valores com virgula ("1.234,56") normalizados para float
- [ ] RelatorioExportService gera arquivos validos
- [ ] Arquivos gerados nos testes sao limpos apos execucao

---

### TICKET 3.3 — Teste de integracao do fluxo completo

**Prioridade:** Alta
**Dependencias:** Ticket 3.2 (precisa das fixtures)

**Descricao:**
Testar o fluxo completo de ponta a ponta: upload -> configurar -> processar -> download.

**Acoes:**
1. Criar `test/integration/conciliacao_flow_test.rb`
2. Testar o fluxo completo:
   - POST `/upload` com 2 fixtures -> redirect para `/configurar`
   - GET `/configurar` -> mostra headers corretos
   - POST `/processar` com configuracao de colunas -> mostra resultados
   - GET `/download/:uuid/conciliados` -> retorna arquivo .xlsx
   - GET `/download/:uuid/pendentes` -> retorna arquivo .xlsx
3. Testar cenarios de erro:
   - Upload sem arquivos -> flash error
   - Sessao expirada -> redirect para root
   - Download com UUID invalido -> erro

**Arquivos:**
- Novo `test/integration/conciliacao_flow_test.rb`

**Criterios de aceite:**
- [ ] Fluxo completo happy path passando
- [ ] Cenarios de erro cobertos
- [ ] Download retorna content-type correto para .xlsx
- [ ] Sessao limpa corretamente apos erros

---

### TICKET 3.4 — Teste de concorrencia

**Prioridade:** Media
**Dependencias:** Ticket 1.1 (precisa do ambiente)

**Descricao:**
Validar que o app funciona com multiplos usuarios simultaneos sem corrupcao de dados.

**Acoes:**
1. Criar script de teste com `k6`, `wrk` ou `curl` paralelo
2. Testar 3 uploads simultaneos com planilhas de ~1000 linhas cada
3. Monitorar: memoria, tempo de resposta, erros
4. Verificar que UUIDs isolam corretamente os dados entre sessoes

**Arquivos:**
- Novo `script/load_test.sh`

**Criterios de aceite:**
- [ ] 3 uploads simultaneos completam sem erro
- [ ] Memoria do container < 80% do limite
- [ ] Nao ha corrupcao de dados entre sessoes (arquivos nao se misturam)
- [ ] Tempo de resposta p95 < 30s para planilhas de 1000 linhas

---

### TICKET 3.5 — Ambiente de staging + rollback validado

**Prioridade:** Media
**Dependencias:** Ticket 1.1

**Descricao:**
Criar ambiente de staging isolado para validar deploys antes de producao.

**Acoes:**
1. Adicionar segundo Web Service no `render.yaml` para staging
2. Apontar staging para branch `staging`
3. Testar ciclo: deploy v1 -> deploy v2 -> rollback para v1
4. Verificar que disco persistente sobrevive ao rollback
5. Documentar runbook de rollback

**Arquivos:**
- `render.yaml` (adicionar staging service)
- Novo `docs/runbook_rollback.md`

**Criterios de aceite:**
- [ ] Ambiente staging funcional e isolado de producao
- [ ] Rollback executado com sucesso via Render dashboard
- [ ] Disco persistente preservado apos rollback
- [ ] Runbook documentado com passo a passo

---

## FASE 4 — Evolucao Futura (pos go-live)

> Estes tickets sao referencia para evolucao futura. Nao sao necessarios para o primeiro deploy.

### TICKET 4.1 — Migrar armazenamento para Object Storage (S3/R2)

**Descricao:** Substituir `File.binwrite` e `send_file` por Active Storage ou client direto de S3/Cloudflare R2. Remove dependencia de disco local e habilita multiplas replicas.

**Beneficio:** Escalabilidade horizontal, arquivos acessiveis de qualquer instancia.

---

### TICKET 4.2 — Processamento assincrono com Active Job

**Descricao:** Mover o pipeline de conciliacao para background job usando Solid Queue (Rails 8 nativo) ou Sidekiq. A view mostra status de processamento com polling ou SSE.

**Beneficio:** Upload retorna imediatamente, usuario ve progresso, sem risco de timeout.

---

### TICKET 4.3 — Sessao distribuida

**Descricao:** Substituir sessao cookie com paths locais por sessao que armazena apenas UUIDs. Os paths sao derivados do UUID + configuracao da plataforma de storage.

**Beneficio:** Compativel com multiplas instancias sem sticky sessions.

---

## Riscos e Pontos de Atencao

| # | Risco | Severidade | Mitigacao |
|---|-------|------------|-----------|
| 1 | Ruby 4.0.1 muito recente — imagem Docker pode nao existir | Alta | Verificar `docker pull ruby:4.0.1-slim` antes de comecar. Se nao existir, usar 3.3.x |
| 2 | Sem testes automatizados | Alta | Ticket 3.1 priorizado em paralelo com Fase 0 |
| 3 | Algoritmo combinatorio O(n^k) — `C(30,6) = 593.775` iteracoes | Media | Rack::Timeout (Ticket 2.2) + monitorar tempo de processamento |
| 4 | CSP vai bloquear JS inline em `configurar.html.erb` | Media | Ticket 0.1 inclui correcao (nonce ou mover para arquivo) |
| 5 | Cookie session limite 4KB | Baixa | OK hoje com uuid+2 paths. Nao adicionar mais dados |
| 6 | Disco persistente Render limitado a 1 instancia | Media | Para escalar, implementar Ticket 4.1 (Object Storage) |

---

## Checklist de Verificacao Final

Apos implementar todos os tickets:

- [ ] CI verde (linters + security scanners + testes)
- [ ] Deploy em staging via push para branch `staging`
- [ ] Fluxo completo: upload -> configurar -> processar -> download
- [ ] Logs JSON no Render Log Explorer com request_id
- [ ] HTTPS redirect: `curl -I http://dominio` -> 301
- [ ] Host Authorization: `curl -H "Host: evil.com"` -> 403
- [ ] Upload invalido: arquivo .txt -> flash error
- [ ] Upload grande: arquivo >20MB -> flash error
- [ ] Cleanup de tmp funcionando apos 2h
- [ ] Rollback via Render dashboard testado
- [ ] 3 uploads simultaneos sem erro
- [ ] Aviso LGPD visivel na tela de upload
