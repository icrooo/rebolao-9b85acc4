## Botão "Copiar faltantes de hoje" em /admin

Adicionar ao lado de "+ Adicionar jogo", mesma altura, um botão que copia para a área de transferência a lista de usuários aprovados que ainda **não** preencheram 1+ palpites dos jogos de hoje (janela 4h Salvador → 4h do dia seguinte). Cada nome vem com a quantidade de jogos faltantes entre parênteses.

### Avaliação de I/O (resumo)

- Roda **só no clique**, sem polling/realtime/subscription.
- 1 única query: `predictions` filtrado por `match_id in (<=4 ids de hoje)` → ~200 linhas no pior caso.
- `profiles` aprovados e `matches` reaproveitados do estado já carregado da página.
- Impacto desprezível frente ao que `/admin` já faz em mount. Sem risco de gargalo futuro.

### Formato do texto copiado

```
Faltam palpites para hoje (3 jogos):
- Fulano (3)
- Beltrano (2)
- Ciclano (1)
```

Se a lista vier vazia: nada é copiado; toast "Todo mundo já palpitou nos jogos de hoje 🎉".

### Alterações em `src/pages/AdminPage.tsx` (somente frontend)

1. **Imports**: `Copy` de `lucide-react`; `useToast` (se ainda não estiver).

2. **Botão novo** na mesma linha flex do "+ Adicionar jogo":
   - `variant="outline"`, ícone `Copy`, texto "Copiar faltantes de hoje".
   - Estado local `copying: boolean` desabilita durante a operação para evitar cliques múltiplos.
   - Em telas estreitas, o container já existente faz wrap natural.

3. **Handler `handleCopyMissingToday`**:
   - Calcula `cutoffHojeUtc` (07:00 UTC; recua 24h se `now < 07:00 UTC`) e `cutoffAmanhaUtc = cutoffHojeUtc + 24h` — mesma lógica do filtro HOJE em `PredictionsPage` (memória `predictions-filters`).
   - Filtra `matches` (estado existente) para `match_datetime ∈ [cutoffHojeUtc, cutoffAmanhaUtc)` → `todaysMatches`.
   - Se `todaysMatches.length === 0` → toast "Nenhum jogo previsto para hoje." e retorna.
   - Query única:
     ```ts
     supabase.from('predictions')
       .select('user_id, match_id')
       .in('match_id', todaysMatches.map(m => m.id));
     ```
   - Constrói `Map<user_id, Set<match_id>>` com quem palpitou.
   - Para cada profile aprovado já em memória, calcula `missingCount = todaysMatches.length - palpitadosNoDia`. Mantém quem tem `missingCount >= 1`.
   - Ordena por `missingCount desc`, depois `name asc`.
   - Monta o texto no formato acima e chama `navigator.clipboard.writeText(...)`.
   - Toast: "Copiado! N pessoa(s) faltando palpitar." ou erro genérico se a clipboard falhar.

4. **Fallback de clipboard**: em contexto sem `navigator.clipboard` (raro em HTTPS moderno), mostrar toast de erro pedindo para tentar de novo. Sem `document.execCommand` legacy.

### Fora de escopo

- Sem mudanças no banco, RLS, funções ou edge functions.
- Sem RPC dedicada (desnecessária dado o volume).
- Sem integração direta com WhatsApp.
- Sem histórico/log de quem foi alertado.
