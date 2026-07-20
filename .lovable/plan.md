# Correções de segurança — plano

Objetivo: fechar os 9 issues restantes (sem ligar HIBP) sem quebrar nada da experiência atual, e mantendo você como admin.

## O que muda para o usuário
Nada visível. Todas as mudanças são no backend (permissões e políticas). Fluxos afetados:
- Login/aprovação: idêntico.
- Ranking, palpites, /all-predictions, /admin: idênticos.
- Você continua admin (o guard é `has_role(auth.uid(), 'admin')`, que lê `user_roles` — nada muda nessa tabela).

## Bloco A — Migration única (SQL)

### 1. `refresh_ranking_state()` — bloquear chamada direta pelo cliente
```sql
REVOKE EXECUTE ON FUNCTION public.refresh_ranking_state() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.refresh_ranking_state() TO service_role;
```
Por que não quebra: só é chamada por outras funções `SECURITY DEFINER` (admin_start_match, admin_finish_match, admin_adjust_score, admin_restart_match, admin_approve_user, admin_unapprove_user). Funções SECURITY DEFINER executam com privilégios do owner (postgres) → continuam podendo chamar. Nenhum código do frontend chama diretamente.

### 2. Esconder `profiles.email` do cliente (coluna-nível, mantém RLS atual)
```sql
REVOKE SELECT (email) ON public.profiles FROM anon, authenticated;
```
Por que não quebra: varredura no código (`rg`) confirma que nenhuma tela lê `email` via `from('profiles')`. `/admin` lê email pela RPC `admin_get_profiles` (SECURITY DEFINER, gated por admin) — continua funcionando. AuthContext seleciona só `user_id, name, is_approved`. AllPredictions/Home/Predictions selecionam só `user_id, name`.

### 3. Reforçar `search_path` em funções sinalizadas pelo linter
Rodar `supabase--linter` após a migration. Para qualquer função apontada sem `SET search_path`, aplicar `ALTER FUNCTION public.<fn>(<args>) SET search_path = 'public';`. As funções mostradas em contexto já têm — o linter dirá se sobra alguma. Zero impacto funcional.

### 4. Verificação pós-migration
- `SELECT has_function_privilege('authenticated','public.refresh_ranking_state()','EXECUTE');` → `false`.
- `SELECT has_column_privilege('authenticated','public.profiles','email','SELECT');` → `false`.
- Testar no preview: abrir /ranking, /predictions, /all-predictions e /admin. Todas devem carregar normalmente.

## Bloco B — Findings marcados como não aplicáveis
Via `security--manage_security_finding` + `security--update_memory` (para não voltarem em scans futuros):

- **`server-time` edge function pública**: já valida JWT via `getClaims` no início do handler (linhas 14–35 do `supabase/functions/server-time/index.ts`). Não há dado sensível no response (só um `now` ISO). Motivo do ignore: proteção já existe.
- **`realtime.messages` acessível**: o app não usa Realtime Broadcast/Presence — só Postgres Changes (que passam por RLS das tabelas). Motivo do ignore: superfície não utilizada.

## Não incluído (por sua instrução)
- Leaked Password Protection (HIBP) — fica desligado.

## Ordem de execução
1. Migration do Bloco A.
2. Rodar linter; se restar função sem `search_path`, migration curta de follow-up.
3. Marcar os 2 findings do Bloco B como ignorados + atualizar security memory.
4. Reportar contagem final de issues.
