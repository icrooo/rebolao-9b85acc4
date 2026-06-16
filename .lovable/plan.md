## Abordagem proposta

Substituir a lógica atual de "posição anterior diferente" por **snapshots de ranking por bloco de horário de partida**. Cada bloco = `date_trunc('minute', match_datetime)`. O snapshot é criado **uma única vez**, no instante em que a **primeira** partida daquele minuto é iniciada, e fica congelado até que comece um novo bloco.

A seta no ranking geral passa a comparar:
`posição_no_snapshot_do_bloco_ativo  −  posição_atual`

Onde "bloco ativo" = o snapshot mais recente já criado (assim ele continua válido depois das partidas terminarem, até que outro bloco em outro horário comece).

---

## Impacto no Disk I/O (resposta direta)

**Praticamente neutro, com leve tendência a reduzir.**

- **Escrita no start da partida:** 1 INSERT em massa (~N usuários aprovados, dezenas de linhas) **somente** no primeiro jogo de cada bloco. Para o 2º jogo simultâneo: zero escrita (já existe). Hoje, cada `admin_start_match` já dispara `refresh_ranking_state` que faz UPSERT em `ranking_position_state` (também ~N linhas) — ordem de grandeza idêntica.
- **Leitura no ranking:** o JOIN atual com `ranking_position_state` é trocado por JOIN com `ranking_kickoff_snapshots WHERE block_time = (SELECT MAX(block_time) …)`. Com índice em `block_time DESC` é uma única tupla + index scan — custo equivalente.
- **Possível ganho:** `refresh_ranking_state` deixa de precisar manter `ranking_position_state` (posso remover esse UPSERT). Como ele roda a cada gol/ajuste durante jogos ao vivo, isso elimina ~N writes por evento de placar. Pequeno, mas é redução real.

**Conclusão:** não introduz novo gargalo. Mantém o I/O atual ou economiza um pouco durante jogos ao vivo.

---

## Mudanças (técnico)

### 1. Nova tabela
```text
ranking_kickoff_snapshots
  block_time  timestamptz   -- date_trunc('minute', match_datetime)
  user_id     uuid
  position    int
  created_at  timestamptz
  PK (block_time, user_id)
  INDEX (block_time DESC)
```
RLS: SELECT para `authenticated` (precisa ler para montar a seta). INSERT/UPDATE/DELETE só via funções `SECURITY DEFINER`.

### 2. Nova função `ensure_kickoff_snapshot(p_match_id uuid)`
- Calcula `v_block := date_trunc('minute', match_datetime)`.
- `INSERT … SELECT user_id, position FROM ranking_cache … ON CONFLICT (block_time, user_id) DO NOTHING` — se já existir bloco, é no-op atômico (resolve corrida entre dois jogos simultâneos).
- Importante: roda **antes** de `calculate_live_scores` para capturar o ranking pré-pontuação.

### 3. Ajuste em `admin_start_match` e `admin_restart_match`
- `admin_start_match`: chamar `ensure_kickoff_snapshot(p_match_id)` **antes** de `calculate_live_scores` + `refresh_ranking_state`.
- `admin_restart_match`: não cria snapshot (apenas reseta).
- `admin_finish_match`: **não mexe** no snapshot — a seta deve continuar valendo após o término.

### 4. Reescrever `get_ranking_with_change`
Substituir o JOIN com `ranking_position_state` por:
```sql
WITH active_block AS (
  SELECT MAX(block_time) AS bt FROM ranking_kickoff_snapshots
)
… LEFT JOIN ranking_kickoff_snapshots s
       ON s.user_id = c.user_id
      AND s.block_time = (SELECT bt FROM active_block)
…
out_position_change = s.position - c.position   -- NULL se não houver snapshot ainda
```
Comportamento preservado para `p_group_id IS NOT NULL` (grupos): continua retornando `NULL` na variação, como hoje.

### 5. `ranking_position_state`
- Pode ser **mantida e ignorada** (zero impacto) ou removida em migração futura. Recomendo manter agora e só parar de alimentá-la em `refresh_ranking_state` numa próxima limpeza, pra reduzir risco.
- Para já ganhar I/O: posso remover o UPSERT dela em `refresh_ranking_state` já nesta PR. **Pergunta abaixo.**

### 6. Frontend (`RankingPage.tsx`)
Nenhuma mudança lógica. O campo `out_position_change` continua sendo lido igual. Apenas o significado muda (referência = snapshot do bloco, não posição anterior).

---

## Casos de borda cobertos

| Cenário | Comportamento |
|---|---|
| Jogo inicia 0×0, usuário sobe 6º→4º | ↑2 |
| Placar muda, usuário 6º→2º | ↑4 |
| Volta para 6º | traço (change = 0) |
| Cai para 9º | ↓3 |
| Partida finaliza com ele em 9º | continua ↓3 (snapshot intacto) |
| 2 jogos simultâneos às 16:00 | mesmo `block_time`, `ON CONFLICT DO NOTHING` garante 1 snapshot |
| Próximo bloco às 19:00 inicia | novo snapshot, seta passa a referenciar 19:00 |
| Ranking do dia / por grupo | inalterados (não usam snapshot) |

---

## Perguntas antes de eu codar

1. **Backfill inicial:** quando a migração rodar, ainda não haverá snapshot. Quer que eu **crie um snapshot "semente"** com a posição atual de todos (block_time = `now()` truncado ao minuto), para as setas funcionarem imediatamente? Ou prefere setas em branco até o próximo `admin_start_match`?
2. **Aproveitar e remover o UPSERT em `ranking_position_state`** dentro de `refresh_ranking_state` para economizar I/O extra durante jogos ao vivo? (Tabela continua existindo, só para de receber escrita.)
3. **Reset de bloco:** se o admin restartar a única partida de um bloco, o snapshot daquele bloco deve ser **apagado** (volta a referenciar o bloco anterior)? Minha proposta default: sim, deletar o snapshot quando não restar nenhuma partida iniciada naquele `block_time`.
