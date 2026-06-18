## Ajustes em /predictions

### 1. Tags dos grupos de amizade no próprio usuário
Em `src/pages/PredictionsPage.tsx`, dentro de `fetchSharedGroups` (linha ~292), há um `if (m.user_id === user.id) return;` que pula o próprio usuário ao montar o mapa de grupos compartilhados. Por isso a tag de grupo nunca aparece ao lado do nome do usuário logado.

**Mudança:** remover esse `return`, fazendo o próprio `user.id` ser incluído no `sharedGroupsByUser`. As tags então renderizam normalmente na linha do usuário em "Ver palpites" (linha ~199-201).

### 2. Penalidade de -2 em roxo
Em `src/pages/PredictionsPage.tsx`, componente `ScoreBadge` (linha 47):

```ts
const cls = points === 5 ? 'score-badge-5'
  : points === 2 ? 'score-badge-2'
  : points === -1 ? 'score-badge-negative'
  : 'score-badge-0';
```

Hoje `-2` cai no `else` e usa `score-badge-0` (cinza). Vou adicionar um ramo:

```ts
: points === -2 ? 'bg-score-missed text-white'
```

Assim a badge `-2 pts` fica no mesmo roxo já usado para o `-x-` em "Ver palpites" (token `--score-missed`).

### Escopo
- Apenas `src/pages/PredictionsPage.tsx`.
- Sem mudanças de backend, lógica de pontuação ou estilos globais.