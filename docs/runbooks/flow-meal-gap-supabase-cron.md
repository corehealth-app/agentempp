# Agendamento dos lembretes do Flow em homologação

A migration `20261127175843_flow_meal_gap_supabase_cron.sql` instala o
transporte desligado no Supabase de homologação `xitugspwfxkcluxvrdeg`.
O disparo usa o worker Vercel `prj_0SRds3zTc57EB0sExjYPygKGEgBx` e o
mesmo serviço de envio APNs. Usa o bypass de projeto já guardado no Vault
pelo processamento de mídia. As chaves APNs ficam no worker.

1. Conferir o alvo e aplicar apenas a migration listada. Hospedar o worker
   como Preview com `MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED=true` e
   `MOBILE_FLOW_MEAL_GAP_TRANSPORT=supabase-cron`. Confirmar que o endpoint
   `/api/internal/flow-meal-gap` responde 401 sem a capacidade de despacho.
2. Confirmar o projeto do deployment e gravar somente seu hostname imutável
   em `private.flow_meal_gap_cron.worker_host`. Agendar
   `performe-flow-meal-gap` com `0 * * * *` e o comando
   `SELECT private.dispatch_flow_meal_gap_cron();`. No Inngest, o conjunto
   habilitado para esse transporte omite o lembrete.
3. Conferir `cron.job_run_details`, o código retornado pelo worker em
   `net._http_response` usando o `request_id` e os recibos APNs, sem
   extrair cabeçalhos, chaves ou identificadores pessoais. Confirmar no
   build TestFlight que a notificação chega com o app fechado, abre o Flow
   correto e é suprimida após registrar ou pular a refeição.

Para desativar, limpar `worker_host`, `dispatch_sha256` e `expires_at` da
linha de controle e remover somente o cron `performe-flow-meal-gap`.
A execução já autenticada pode concluir. Os recibos, preferências e crons
de mídia continuam em uso. Em uma troca de worker, deixar a execução atual
concluir antes de alterar o hostname.
