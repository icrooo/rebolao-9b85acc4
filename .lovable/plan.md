## Objetivo
Na aba **Jogos** do `/admin`, reorganizar a lista para que jogos encerrados fiquem dentro de um `Collapsible` recolhido por padrão, posicionado **acima** dos jogos em andamento/futuros. Eliminar a lógica atual que puxa jogos em andamento para o topo.

## Alterações

### `src/pages/AdminPage.tsx`

1. **Separar os jogos em 3 grupos** via `useMemo`:
   - `finishedMatches`: `is_finished === true`
   - `activeMatches`: `is_started === true && is_finished === false`
   - `upcomingMatches`: `!is_started`

2. **Remover o `sortedMatches` atual** (linhas 234-241) que prioriza jogos em andamento no topo. Substitui-lo por ordenação puramente cronológica dentro de cada grupo.

3. **Inserir um `Collapsible`** (importar de `@/components/ui/collapsible`) **acima** do mapeamento de jogos ativos/futuros. O conteúdo desse Collapsible é a lista de `finishedMatches`.
   - O trigger deve exibir um título estilizado como "Encerrados (N)" com um indicador de expandir/recolher.
   - Estado `openFinished` iniciado como `false` (recolhido por padrão).
   - Manter o mesmo estilo de card (`glass-card p-4`) dentro do Collapsible.

4. **Renderizar jogos em andamento + futuros** logo abaixo do Collapsible, em ordem cronológica (mais próximos primeiro), sem pular para o topo. Manter o card e comportamento atuais (botões de placar, iniciar, encerrar, reiniciar, editar).

5. **Limpar**: o estado e a função `sortedMatches` que reordenam ao iniciar um jogo se tornam desnecessários — a lista permanece em ordem cronológica estável.

## Detalhes técnicos
- O componente `Collapsible` já existe em `src/components/ui/collapsible.tsx` (Radix UI).
- Estilo do trigger: usar `glass-card` ou um header semelhante ao restante do app, com `ChevronDown` que rotaciona conforme estado.
- Nenhuma mudança de backend ou banco de dados.
- Nenhum impacto na aba de usuários.