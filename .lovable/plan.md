# Ajustes de UI

## 1. `/predictions` — remover filtro "GRUPOS"
- `src/pages/PredictionsPage.tsx` linha 33: alterar `FILTERS` para `['PRÓXIMOS JOGOS', 'TODOS', 'MATA-MATA']`.
- Se o filtro atual salvo for `'GRUPOS'`, o estado inicial já é `'PRÓXIMOS JOGOS'`, então sem migração. Nenhuma outra lógica precisa mudar (o branch `case 'GRUPOS'` simplesmente vira código morto — removo junto).

## 2. `/all-predictions` — sticky header + fix do scroll lateral
Problema atual: o wrapper usa `overflow-x-auto -mx-4 px-4`. Como o `padding` fica **dentro** do contêiner de scroll, `position: sticky; left: 0` gruda na borda interna após o padding — então, ao rolar para a direita, as células das colunas seguintes aparecem "vazando" sob os 16px de padding esquerdo, antes da coluna de nomes.

Mudanças em `src/pages/AllPredictionsPage.tsx`:
- Trocar o wrapper `<div className="overflow-x-auto -mx-4 px-4">` por `<div className="overflow-x-auto -mx-4">` e adicionar `pl-4` apenas na primeira `<th>`/`<td>` (a coluna "Nome") — assim o padding vira parte da própria célula sticky e some o vazamento à esquerda.
- Tornar o cabeçalho fixo verticalmente: adicionar `sticky top-0 z-20 bg-background` em todos os `<th>`; a célula do canto (Nome) recebe `z-30` (sticky em duas direções).
- Garantir que `bg-background` cubra completamente as células sticky em ambos os temas (já é o caso) e remover qualquer transparência herdada.

Resultado: cabeçalho permanece visível ao rolar para baixo; coluna de nomes permanece visível ao rolar para a direita, sem conteúdo aparecendo à sua esquerda.

## 3. `/admin` — jogo em andamento no topo
Em `src/pages/AdminPage.tsx`, ao renderizar a lista de jogos (aba "matches"), aplicar ordenação derivada:
- Jogos com `is_started === true && is_finished === false` aparecem primeiro (mantendo ordem cronológica entre si, caso haja mais de um).
- Os demais seguem a ordem cronológica original (`match_datetime` asc), que já vem do backend.
- Implementação: `const sortedMatches = useMemo(() => [...matches].sort((a,b) => { const aLive = a.is_started && !a.is_finished; const bLive = b.is_started && !b.is_finished; if (aLive !== bLive) return aLive ? -1 : 1; return new Date(a.match_datetime).getTime() - new Date(b.match_datetime).getTime(); }), [matches]);` e iterar sobre `sortedMatches` no `.map`.
- Ao encerrar (`is_finished = true`), o jogo deixa de ser "live" e volta automaticamente à posição cronológica. Sem alteração de schema.

## 4. Header — bump de versão
- `src/components/AppLayout.tsx` linha 74: trocar `v. 1.1 beta` por `v. 1.2`.

## Fora de escopo
- Nenhuma mudança de backend, migrations ou realtime.
- Nenhuma alteração nos cálculos de pontuação ou ranking.
