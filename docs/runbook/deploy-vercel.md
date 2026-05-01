# Deploy do Admin no Vercel

## 1. Conectar repositório

No Vercel team da CoreHealth:

1. **Add New → Project**
2. Importar `corehealth-app/agentempp`
3. **Root directory:** `apps/admin`
4. **Framework Preset:** Next.js (auto-detectado)
5. **Build & Output Settings:** já vêm do `apps/admin/vercel.json`

## 2. Variáveis de ambiente

Em **Project Settings → Environment Variables**, adicione (Production + Preview):

```
NEXT_PUBLIC_SUPABASE_URL=https://xuxehkhdvjivitduarvb.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<publishable key>
SUPABASE_SERVICE_ROLE_KEY=<service role JWT>
OPENROUTER_API_KEY=<sk-or-v1-…>
GROQ_API_KEY=<gsk_…>
```

> ⚠️ **Antes de subir para produção**, regenere as chaves que foram expostas
> em chat e cadastre as novas via `/settings/api-keys` quando o app estiver
> rodando.

## 3. Domínio

- **Domains** → adicionar (ex: `admin.corehealth.app`)
- DNS no provedor: CNAME → `cname.vercel-dns.com`
- HTTPS automático

## 4. Auth callback

No Supabase Dashboard:

- **Authentication → URL Configuration**
- **Site URL:** `https://admin.corehealth.app`
- **Redirect URLs:** adicionar `https://admin.corehealth.app/auth/callback`

## 5. Branches

- `main` → Production
- PRs → Preview deploys automáticos
- Cada preview tem URL própria (útil para revisar antes de merge)

## 6. Pós-deploy

```bash
# Confirmar que está OK
curl -I https://admin.corehealth.app

# Logs em tempo real
vercel logs --follow
```

## 7. Custos

- Vercel Hobby: **gratuito** até 100 GB-Hours/mês de compute
- Para o admin com 1-3 usuários internos, fica dentro do free tier
- Se passar para Pro ($20/mês): preview deploys ilimitados, analytics, edge config
