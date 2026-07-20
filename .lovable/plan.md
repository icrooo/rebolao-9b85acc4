# Plano — 4 issues restantes do scan

Depois da varredura das RPCs `SECURITY DEFINER` no banco e do código da edge function, os 4 alertas remanescentes são **falsos positivos** para este app. Nenhum requer mudança de código ou migration — mexer para "resolver" pioraria a experiência (quebraria login, ranking ou admin). O plano é documentar e silenciar via `manage_security_finding` + `update_memory`.

## O que muda para o usuário
Nada. Sem migrations, sem redeploy de função, sem alteração de UI.

## Issue 1 — `server-time` edge function sem auth
- **Realidade:** `supabase/functions/server-time/index.ts` **já valida JWT** (linhas 14–35: exige `Authorization: Bearer` e valida via `supabase.auth.getClaims(token)`; retorna 401 se inválido).
- **Resposta única no sucesso:** `{ now: <ISO timestamp> }` — sem dado sensível.
- **Ação:** `ignore` com explicação apontando as linhas do guard. O scanner é heurístico e não detectou o `getClaims`.

## Issue 2 — `realtime.messages` sem RLS
- **Realidade:** o app não usa Broadcast/Presence do Realtime. As subscrições ativas usam apenas Postgres Changes em tabelas cuja RLS já cobrimos (`matches`, `scores`, `ranking_pulse`, etc.).
- **Ação:** `ignore` — superfície não utilizada; adicionar policies em `realtime.messages` não traria valor.

## Issue 3 — "Public Can Execute SECURITY DEFINER Function" (anon)
- **Realidade:** hoje **apenas `get_approved_count`** é executável por `anon`. Ela retorna só um inteiro (contagem de usuários aprovados) e é usada pela `/` (landing) para mostrar "N jogadores". Sem dado sensível.
- **Ação:** `ignore` com essa justificativa. Revogar quebraria a landing pública.

## Issue 4 — "Signed-In Users Can Execute SECURITY DEFINER Function" (authenticated)
- **Realidade:** as funções acessíveis a `authenticated` são todas necessárias e **auto-guardadas**:
  - `admin_*` (7 funções): verificam `has_role(auth.uid(),'admin')` no topo — usuário comum recebe erro.
  - `get_ranking`, `get_ranking_with_change`, `get_user_rank`: leem apenas dados públicos do bolão (nome, pontos, posição), usados por `/ranking` e header.
  - `has_role`, `is_approved`: retornam booleans do próprio usuário (usados por RLS).
  - `admin_get_profiles`: filtra por admin internamente.
  - Funções internas de manutenção (`refresh_ranking_state`, `calculate_*`, `snapshot_*`, triggers, `handle_new_user`) **já estão restritas a service_role/postgres** — a auditoria confirmou.
- **Ação:** `ignore` com essa justificativa (é um alerta genérico do linter — cada função foi revisada individualmente).

## Detalhes técnicos
1. Chamar `security--manage_security_finding` com 4 operações `ignore`, uma por finding, com a explicação correspondente.
2. Chamar `security--update_memory` acrescentando as decisões acima ao memory (mantendo o que já está lá), para que scans futuros não reabram.
3. Não roda `supabase--migration`, não altera `supabase/config.toml`, não mexe em `server-time/index.ts`.

## Fora de escopo
- Leaked Password Protection (HIBP) — por sua instrução, permanece desligado.
