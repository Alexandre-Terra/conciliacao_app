# Runbook — Staging e Rollback no Render

> **Aplicável a:** `conciliacao-app` (produção) e `conciliacao-app-staging` (staging)
> **Tempo estimado de rollback:** 2–5 minutos

---

## Ambientes

| Serviço                    | Branch    | URL                                        | Disco                       |
|----------------------------|-----------|--------------------------------------------|------------------------------|
| `conciliacao-app`          | `main`    | `conciliacao-app.onrender.com`             | `conciliacao-tmp`            |
| `conciliacao-app-staging`  | `staging` | `conciliacao-app-staging.onrender.com`     | `conciliacao-tmp-staging`    |

Os dois ambientes são **completamente isolados**: discos separados, subdomínios separados, nenhum dado compartilhado.

---

## Fluxo de deploy recomendado

```
feature-branch → PR → merge em staging → validar em staging → PR → merge em main → produção
```

### 1. Promover para staging

```bash
git checkout staging
git merge --no-ff minha-feature
git push origin staging
# Render detecta o push e deploya automaticamente em conciliacao-app-staging
```

### 2. Validar em staging

```bash
# Healthcheck
curl -I https://conciliacao-app-staging.onrender.com/up
# Esperado: HTTP/2 200

# Teste funcional: abrir o app no browser e fazer uma conciliação de teste
# URL: https://conciliacao-app-staging.onrender.com
```

**Checklist mínimo antes de promover para produção:**
- [ ] Healthcheck `/up` retorna 200
- [ ] Upload de arquivos `.xls` e `.xlsx` funciona
- [ ] Conciliação processa sem erro 500
- [ ] Download dos relatórios funciona
- [ ] Logs no Render Log Explorer sem erros inesperados

### 3. Promover staging → produção

```bash
git checkout main
git merge --no-ff staging
git push origin main
# Render deploya automaticamente em conciliacao-app
```

---

## Quando usar este runbook

- Deploy recente introduziu bug em produção
- App retorna 5xx após um deploy
- Healthcheck `/up` falhou após deploy

---

## Pré-requisito: configurar deploy via CI (não auto-deploy)

Para que um CI com falha nunca chegue a fazer deploy, o Render deve estar configurado
para **não** fazer auto-deploy automático. O deploy é acionado pelo workflow de CI.

**Configuração única (fazer uma vez no painel do Render):**

1. Render dashboard → selecionar o serviço `conciliacao-app`
2. **Settings → Build & Deploy → Auto-Deploy → desabilitar**
3. **Settings → Deploy Hook → copiar a URL**
4. GitHub repo → **Settings → Secrets and variables → Actions**
5. Criar secret `RENDER_DEPLOY_HOOK_URL` com a URL copiada

---

## Rollback via Render Dashboard

### Passo 1 — Acessar o histórico de deploys

1. Render dashboard → serviço `conciliacao-app`
2. Menu lateral → **Deploys**
3. Lista mostra os últimos deploys com status, timestamp e commit SHA

### Passo 2 — Identificar a versão estável

Localize o último deploy com status `Live` antes do deploy problemático.
O Render mantém histórico das últimas **~20 versões**.

### Passo 3 — Reverter

1. Clique no deploy estável desejado
2. Botão **"Rollback to this deploy"** (canto superior direito)
3. Confirme na modal

O Render ativa a imagem Docker já buildada daquele deploy — **não há rebuild**.
O rollback leva aproximadamente **1–2 minutos**.

### Passo 4 — Verificar

```bash
# Checar healthcheck
curl -I https://conciliacao-app.onrender.com/up

# Verificar header para confirmar qual versão está no ar
curl -s https://conciliacao-app.onrender.com/up
```

O painel do Render mostrará o deploy revertido como `Live`.

---

## Rollback via API do Render (alternativa CLI)

```bash
# Listar deploys (requer RENDER_API_KEY e SERVICE_ID)
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/services/$SERVICE_ID/deploys?limit=10" \
  | jq '.[] | {id: .deploy.id, status: .deploy.status, createdAt: .deploy.createdAt}'

# Fazer rollback para um deploy específico
curl -s -X POST \
  -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" \
  "https://api.render.com/v1/services/$SERVICE_ID/deploys/$DEPLOY_ID/rollback"
```

`RENDER_API_KEY`: Render dashboard → Account Settings → API Keys
`SERVICE_ID`: URL do serviço no painel (ex: `srv-abc123`)

---

## Disco persistente durante rollback

O disco persistente (`/rails/tmp/conciliacao`) **não é afetado** pelo rollback.
Arquivos em processamento no momento do rollback podem ficar órfãos — serão removidos
automaticamente pelo cron de limpeza (TTL 2h, Ticket 2.1).

---

## Rollback em staging

O mesmo procedimento se aplica ao staging. No passo 1, acesse o serviço
`conciliacao-app-staging` no painel. A URL de verificação é:

```bash
curl -I https://conciliacao-app-staging.onrender.com/up
```

Como staging não tem usuários reais, o rollback aqui é um **ensaio** — use para
confirmar que a versão anterior funciona antes de fazer rollback em produção.

---

## Verificar disco persistente após rollback

O disco (`/rails/tmp/conciliacao`) sobrevive ao rollback porque é um volume
independente da imagem Docker. Arquivos de conciliação em andamento no momento
do rollback ficam acessíveis normalmente.

**Para confirmar via Render Shell** (se disponível no plano):

```bash
ls /rails/tmp/conciliacao/   # deve listar os UUIDs de sessões ativas
```

Arquivos órfãos (sessões de usuários que não concluíram) são removidos pelo
cron de limpeza (TTL 2h em produção, 1h em staging — ver Ticket 2.1).

---

## Após o rollback — corrigir e redeployer

1. Criar branch a partir do commit estável
2. Corrigir o problema
3. Abrir PR para `staging` → validar
4. Abrir PR para `main` → merge → produção

**Nunca force-push em `main` ou `staging`** para "desfazer" um commit — use
rollback pelo Render e corrija via PR.
