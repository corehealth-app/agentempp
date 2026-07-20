# ADR 012 — Mídia mobile privada atrás do BFF

- Status: Accepted
- Data: 2026-07-20
- Decisores: Eduardo

## Contexto

O BodyFlow app-first precisa receber fotos de refeições, reavaliações corporais,
academia e notas de áudio sem depender do WhatsApp. Fotos corporais são dados
sensíveis. O app não pode possuir `service_role`, paths enumeráveis ou URLs
públicas permanentes. Também não é seguro usar `storage.objects.owner_id` como
fonte de ownership, porque objetos operados pelo backend podem não receber owner
do paciente.

## Decisão

1. Cinco buckets separados permanecem privados: `meal-photos`,
   `body-checkin-photos`, `gym-photos`, `audio-notes` e `content-covers`.
2. `public.media_assets` é o catálogo canônico de paciente, objeto, tipo,
   tamanho, estado, retenção e resultado. O path é imutável e gerado pelo BFF.
3. Pacientes podem ler apenas os próprios metadados sob RLS. Nenhuma role de
   cliente pode inserir, alterar ou excluir o catálogo, nem operar diretamente
   em `storage.objects`.
4. O BFF emite signed upload de duas horas e signed download de 60 segundos para
   fotos corporais ou 300 segundos para as demais mídias. A capacidade de upload
   não é persistida no ledger idempotente; replays geram outra URL para o mesmo
   ativo.
5. A conclusão do upload compara MIME e bytes reais com a declaração. O worker
   também valida magic bytes antes de qualquer chamada de IA.
6. Legenda e foto são persistidas como um único ativo. A legenda não circula no
   evento Inngest; o worker a carrega pelo ID e a passa como contexto, evitando
   dupla contabilização.
7. Processamento usa claim transacional por ativo e request. Retry do mesmo
   evento pode retomar falha transitória; depois de `failed`, um novo pedido
   explícito pode criar outro claim. Eventos concorrentes não tomam claim ativo.
8. Retenção automática e exclusão de conta removem o objeto físico antes do
   catálogo. O FK com `users` usa `RESTRICT` para impedir órfãos silenciosos.
9. `content-covers` fica fora da API paciente até existir CMS e autorização de
   conteúdo próprios.

## Consequências

- **+** Nenhuma credencial privilegiada ou URL permanente entra no app.
- **+** Ownership independe de metadados implícitos do Storage.
- **+** Foto + texto mantêm um único contexto e uma única análise.
- **+** Falhas de upload, processamento e retenção são recuperáveis e auditáveis.
- **+** Fotos corporais recebem TTL mais curto e isolamento operacional.
- **−** Upload exige duas chamadas ao BFF, além do envio direto ao Storage.
- **−** O app precisa respeitar MIME/tamanho exatos e concluir explicitamente.
- **−** Signed URLs são capacidades temporárias e exigem disciplina de logs no
  cliente e no backend.

Nenhuma migration foi aplicada em produção e nenhum deploy foi feito por esta
decisão.
