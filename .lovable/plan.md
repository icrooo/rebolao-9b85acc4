## Objetivo
Substituir os filtros atuais de `/predictions` (`PRÓXIMOS JOGOS`, `TODOS`, `MATA-MATA`) por: `ONTEM`, `HOJE`, `AMANHÃ`, `TODOS`, com `HOJE` selecionado por padrão e considerando a hora de corte de 4h da manhã de Salvador (UTC-3, ou seja, 7h UTC). Em `TODOS`, agrupar todos os jogos já encerrados em um `Collapsible` recolhido por padrão, no mesmo estilo do `/admin`.

## Alterações em `src/pages/PredictionsPage.tsx`

1. **Constante de filtros** (linha 33): trocar para
   ```ts
   const FILTERS = ['ONTEM', 'HOJE', 'AMANHÃ', 'TODOS'] as const;
   ```
   Remover `MATA-MATA` e referências a `KNOCKOUT_PHASES` dentro do filtro (manter o import se ainda usado em outro lugar; remover se ficar órfão).

2. **Estado inicial** (linha 229): `useState<string>('HOJE')`.

3. **Lógica de janela diária de Salvador** — extrair em helper local dentro do `useMemo`:
   - Calcular `cutoffHojeUtc` = 07:00 UTC do dia corrente de Salvador (mesmo cálculo já existente nas linhas 381-389).
   - Derivar:
     - `cutoffOntemUtc = cutoffHojeUtc - 24h`
     - `cutoffAmanhaUtc = cutoffHojeUtc + 24h`
     - `cutoffDepoisUtc = cutoffHojeUtc + 48h`

4. **`filteredMatches`** (linhas 379-406):
   - `HOJE`: jogos com `match_datetime` em `[cutoffHojeUtc, cutoffAmanhaUtc)`, ordem cronológica. Remover o fallback atual de "se vazio, mostrar próximos 4" — `HOJE` deve mostrar somente os de hoje (vazio → estado vazio).
   - `ONTEM`: `[cutoffOntemUtc, cutoffHojeUtc)`, ordem cronológica.
   - `AMANHÃ`: `[cutoffAmanhaUtc, cutoffDepoisUtc)`, ordem cronológica.
   - `TODOS`: todos os jogos em ordem cronológica (mantém comportamento atual). O agrupamento finalizado/não-finalizado é feito na renderização (passo 5), não aqui.

5. **Renderização de `TODOS` com Collapsible para encerrados** (bloco de map em ~linha 468-472):
   - Quando `filter === 'TODOS'`, dividir `filteredMatches` em:
     - `finishedAll`: `is_finished === true`, ordenados cronologicamente (mais antigo primeiro, igual a hoje — mantém previsibilidade da lista).
     - `unfinishedAll`: restantes, em ordem cronológica.
   - Renderizar primeiro um `<Collapsible open={openFinished} onOpenChange={setOpenFinished}>` (estado novo `openFinished`, default `false`) com trigger estilizado tipo "Encerrados (N)" + `ChevronDown` rotacionando, no mesmo padrão do `/admin`. Conteúdo: lista de `finishedAll` usando o mesmo card de match já em uso.
   - Em seguida, renderizar `unfinishedAll` normalmente abaixo.
   - Para os demais filtros (`ONTEM`/`HOJE`/`AMANHÃ`), manter renderização linear atual (sem Collapsible), pois são janelas curtas.

6. **Imports**: adicionar `Collapsible`, `CollapsibleTrigger`, `CollapsibleContent` de `@/components/ui/collapsible` e `ChevronDown` de `lucide-react`, se ainda não importados.

## Observações
- Hora de corte de 4h Salvador = 07:00 UTC (UTC-3, sem DST). O cálculo atual já está correto e será reaproveitado como base para derivar ontem/hoje/amanhã.
- Nenhuma mudança em backend, scoring, ou outras páginas.
- Memória `mem://features/predictions-filters` precisará ser atualizada após a implementação (na fase de build) para refletir os novos filtros.
