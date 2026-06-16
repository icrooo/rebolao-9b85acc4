## Diagnóstico (por que ainda está alto)

Os PRs 1 e 2 atacaram o "ranking em tempo real" e adicionaram índices/cache. Lendo o código atual, sobram **6 fontes de I/O recorrentes** que disparam mesmo com pouco tráfego:

1. **`PredictionsPage.fetchData` recarrega TUDO**
   - Em cada mount, e principalmente após cada `savePrediction` (`await fetchData()` na linha 445), faz 3 selects: `matches *` (toda a tabela), `predictions where user_id`, `scores where user_id`. Cada palpite salvo = 1 full scan de `matches` + leitura de todas as predições/scores do usuário.
   - O realtime de `matches UPDATE` (linha 344) também dispara `fetchMatches()` que faz `select *` da tabela inteira a cada UPDATE — durante "Iniciar/Atualizar partida" no admin isso multiplica.

2. **`RankingPage.refreshLastUpdated`** (linha 147)
   - Roda após **toda** chamada de `fetchRanking` (incluindo as silenciosas do realtime). É um `ORDER BY updated_at DESC LIMIT 1` em `matches`, sem índice em `updated_at` → sort completo da tabela. Hoje executa em loop a cada update de scores/matches.

3. **`RankingPage` tab "Geral" sem grupo ainda passa por RPC**
   - `get_ranking_with_change` continua sendo chamada mesmo quando o resultado é exatamente o que já está em `ranking_cache`. Para o caso global (sem filtro de grupo, sem variação personalizada), poderíamos ler direto do cache como o `PredictionsPage` já faz.

4. **`AllPredictionsPage` carrega TODOS os dados a cada visita**
   - 4 paginadas: `profiles`, `matches` inteiros, **`predictions` inteiras** (N usuários × M jogos), **`scores` inteiros**. Mesmo com realtime incremental, a 1ª visita custa milhares de linhas por sessão/refresh. E `fetchAll` reexecuta a cada mount do componente.

5. **`PredictionsPage.fetchSharedGroups`** roda a cada mount e faz 3 selects (`user_friendship_groups` x2 + `friendship_groups`). Dados muito estáticos.

6. **Subscriptions duplicadas** — `RankingPage`, `PredictionsPage` e `AllPredictionsPage` cada uma escuta `scores` + `matches`. Cada subscrição mantém canal de WAL aberto e gera replicação. Não é DELETE de I/O, mas contribui no orçamento.

Bônus: `getApprovedCount` na AuthPage roda a cada visita; é um count agregado.

---

## Plano (PR 3) — sem mudar UX

Tudo abaixo é frontend + 1 índice + 1 RPC nova. Nenhuma mudança visual.

### A) Stop re-fetching everything

- **`PredictionsPage.fetchData`**
  - Após `savePrediction`, NÃO chamar `fetchData()`. Atualizar localmente o Map de `predictions` (já temos o draft + id retornado pelo upsert). Economia: 1 select `matches *` + 2 selects por save.
  - Trocar `from('matches').select('*')` por `select('id, home_team, away_team, match_datetime, group_name, home_score, away_score, is_finished, is_started)` (sem `updated_at`, `created_at` etc.).
  - Realtime `matches UPDATE`: em vez de `fetchMatches()` full, atualizar somente o match afetado a partir do `payload.new` (igual ao incremental do AllPredictionsPage).

- **`AllPredictionsPage`**
  - Cache em memória (module-level) + `sessionStorage` com TTL curto (30–60s). Se o usuário sair e voltar para a página dentro do TTL, reusa.
  - Restringir colunas/linhas: trazer só matches `is_started OR is_finished OR match_datetime <= now()+10min` (jogos visíveis pelo filtro `isLocked`). Hoje carrega o torneio inteiro mesmo mostrando 0 jogos liberados.
  - Trocar `predictions/scores` full por `.in('match_id', visibleMatchIds)`.

- **`PredictionsPage.fetchSharedGroups`**
  - Cache em memória por sessão (raramente muda; admin altera). Invalidar via realtime em `user_friendship_groups` só quando aplicável.

### B) Cortar `refreshLastUpdated`

- Substituir o `ORDER BY updated_at DESC LIMIT 1` por leitura **derivada do resultado da RPC** (o cache de ranking pode expor `last_refreshed_at`; ou simplesmente usar `Date.now()` do client após cada fetch bem-sucedido — o valor é só "horário do último placar visto").
- Alternativa mínima: criar índice `CREATE INDEX ON matches(updated_at DESC)` e chamar `refreshLastUpdated` **só** quando o usuário troca de aba/grupo, não em cada update silencioso.

### C) Ranking geral sem grupo → ler do cache

- Em `RankingPage`, quando `tab === 'geral' && selectedGroup === 'all'`, ler direto de `ranking_cache` (igual `PredictionsPage`), sem `get_ranking_with_change`. A coluna `positionChange` virá de uma 2ª leitura em `ranking_cache` que já guarda `previous_position` (se ainda não guarda, adicionar à tabela — barato; é atualizada apenas em `refresh_ranking_state`).
- RPC `get_ranking_with_change` continua existindo, só não é chamada nesse caminho quente.

### D) Consolidar subscriptions

- Mover as 3 subscriptions (`PredictionsPage`, `RankingPage`, `AllPredictionsPage`) para **um único channel global** em `AppLayout`/contexto, com event bus interno. Cada página assina o bus local, não o Postgres. Reduz canais de WAL ativos quando o usuário tem múltiplas abas.

### E) AuthPage

- `get_approved_count`: cachear no `sessionStorage` por 60s.

### F) Banco (1 migração mínima)

- `CREATE INDEX IF NOT EXISTS idx_matches_updated_at ON public.matches(updated_at DESC);` (fallback caso B-alternativa seja escolhida).
- Adicionar coluna `previous_position INT` em `ranking_cache` (se ainda não existir) preenchida por `refresh_ranking_state`. Habilita C sem RPC.

---

## Detalhes técnicos

```text
Drivers de I/O hoje (estimativa qualitativa)
┌──────────────────────────────────────┬──────────┬─────────────┐
│ Origem                               │ Freq.    │ Custo/chamada│
├──────────────────────────────────────┼──────────┼─────────────┤
│ Pred.fetchData após save             │ por save │ alto        │
│ Pred.fetchMatches em realtime matches│ por upd. │ alto (full) │
│ Rank.refreshLastUpdated              │ por upd. │ médio (sort)│
│ Rank.get_ranking_with_change         │ por upd. │ alto        │
│ AllPred fetchAll                     │ por visit│ muito alto  │
│ shared_groups                        │ por mount│ baixo       │
└──────────────────────────────────────┴──────────┴─────────────┘
```

Arquivos:
- `src/pages/PredictionsPage.tsx` — remover refetch pós-save, incremental no realtime, cache shared_groups.
- `src/pages/RankingPage.tsx` — eliminar `refreshLastUpdated` no caminho quente, ler `ranking_cache` no caso global.
- `src/pages/AllPredictionsPage.tsx` — cache de sessão + recorte por `visibleMatchIds`.
- `src/pages/AuthPage.tsx` — cache do count.
- `src/components/AppLayout.tsx` (+ novo `src/contexts/RealtimeBus.tsx`) — channel único compartilhado.
- 1 migração: índice em `matches.updated_at` + coluna `previous_position` em `ranking_cache` + ajuste de `refresh_ranking_state` para preenchê-la.

---

## Impacto esperado

- **Disk I/O budget**: queda adicional estimada de **40–60%** sobre o nível atual (de ~85% para algo entre **30% e 50%**), concentrada nos picos durante jogos e nos cliques do admin.
- **Sem mudança de UX**: telas continuam carregando, salvando e exibindo realtime do mesmo jeito.
- **Reversível**: cada item é um patch independente; podemos liberar A→B→C separadamente se quiser monitorar entre eles.

## Fora de escopo

- Não vou trocar Realtime por polling.
- Não vou mudar regras de pontuação, lock, ranking ou layout.
- Não vou criar workers/cron novos.

Aprova o PR 3 inteiro, ou prefere começar só por A+B (o maior ganho)?
