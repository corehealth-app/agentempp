# MICROCOPY JURÍDICA DO ONBOARDING — PERFORME AI

STATUS: MINUTA PARA REVISÃO JURÍDICA — NÃO PUBLICADA
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

Data de aprovação: `[PENDENTE — DATA DE APROVAÇÃO]`
Data de vigência: `[PENDENTE — DATA DE VIGÊNCIA]`

## Copy proposta

| Documento/finalidade | Microcopy pt-BR | Ação conceitual | Ação do runtime | Obrigatório |
| --- | --- | --- | --- | --- |
| Termos de Uso | “Li e aceito os Termos de Uso.” | `accept` | `acceptance` | Sim, se aprovado e incluído no requirement set |
| Política de Privacidade | “Li a Política de Privacidade.” | `acknowledge` | `acknowledgement` | Sim, se aprovado e incluído no requirement set |
| Saúde e IA | “Entendo as limitações do Performe AI e do Flow em relação à saúde e à inteligência artificial.” | `acknowledge` | `acknowledgement` | Sim, se aprovado e incluído no requirement set |
| Dados sensíveis | “Consinto com o tratamento dos meus dados de saúde e corporais conforme descrito.” | `consent` | `consent` | Depende da funcionalidade, base jurídica e requisito aprovados |

## Regras de apresentação

- Toda ação começa desmarcada e exige gesto explícito.
- A tela deve disponibilizar o conteúdo integral ou link HTTPS controlado correspondente aos exatos versão, locale e hash apresentados pelo servidor.
- Não concluir onboarding com documento ausente, versão antiga, hash divergente, ação incompatível ou requirement set incompleto.
- A Política de Privacidade funciona como aviso de transparência. A copy **“Li e aceito a Política de Privacidade” não é recomendada**, pois confunde ciência com aceite contratual ou consentimento.
- O aceite dos Termos não substitui consentimentos específicos.
- Marketing, se futuramente implementado, deve ficar separado, opcional e inicialmente desmarcado. Não faz parte do escopo proposto desta beta.
- Foto e áudio devem usar aviso e ação just-in-time, não o onboarding geral, salvo decisão posterior baseada no fluxo real.

## Chaves documentais propostas e divergências

| Proposta | Compatibilidade atual |
| --- | --- |
| `legal.terms_of_use` | Incompatível: o runtime rejeita pontos; candidato não aprovado `legal_terms_of_use` |
| `legal.privacy_notice` | Incompatível: candidato não aprovado `legal_privacy_notice` |
| `notice.health_and_flow_ai` | Incompatível: candidato não aprovado `notice_health_and_flow_ai` |
| `consent.sensitive_health_data` | Incompatível: candidato não aprovado `consent_sensitive_health_data` |
| `consent.media_processing` | Incompatível e não aprovado como requisito de onboarding; candidato técnico depende da decisão just-in-time |

Versão documental futura proposta: `1.0.0` — **não aprovada**.
Locales documentais: `pt-BR` e `en`; o runtime implementado aceita `pt-BR` e `en-US`, portanto a versão inglesa operacional deve usar `en-US`.
