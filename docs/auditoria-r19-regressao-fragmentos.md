# Auditoria R19 — regressao de fragmentos (16/10/2026)

## Evidencias do ambiente de producao (somente analise)

- 857 campos suspeitos; 508 candidatos `EXPERIMENTAL-FRAGMENTOS`.
- 491/508 candidatos ainda continham pelo menos um dos marcadores `Ã`, `Â`, `Æ`, `â€`, `â‚`, `ï¿½` ou U+FFFD.
- 17/508 nao continham esses marcadores; isto **nao prova** integridade semantica.
- 491 candidatos com residuos: 80.795 edicoes acumuladas nas provas; 17 sem residuos: 2.091 edicoes.
- O algoritmo R19 tinha `score_mojibake($new) === 0` para alguns resultados como `JosÃÃÃâ`. Score zero nao e criterio suficiente.

## Casos sinteticos de regressao

**Devem ser rejeitados como correcao automatica:**
- `JosÃÃÃâ`
- `MÃÃÆ`
- `Jardim SÃÃÆ`
- `PrÃÃÃâ`
- `celular: 16ÃÃââ‚ → ...`

**Devem permanecer elegiveis apenas para revisao (nao aplicar automaticamente):**
- `Rua São Paulo`
- `Consultório`
- `Gregório Magnani`
- `Conexão 24 horas na fibra.`

## Regras de aceite antes de liberar R20

1. Executar testes unitarios reais em PHP 7.4 e PHP 8.0+; nao basta inspecao estatica.
2. Testar `fragmentos_recuperar` com strings originais sinteticas de multiplas camadas, provando que o resultado e exatamente o esperado.
3. Exigir round-trip de cada edicao e preservar segmentos ASCII e HTML, sem inserir, remover ou reordenar bytes ASCII.
4. Testar perda irreversivel (`U+FFFD` e `ï¿½`) e impedir promocao a `CORRIGIVEL` quando a fonte perdeu informacao.
5. Revisar possiveis falsos positivos do filtro conservador: `Ã` e `Â` podem ser caracteres legitimos. Filtro nao e detector universal.
6. Garantir que `--experimental-fragments --apply` nao execute UPDATE enquanto a validacao nao estiver concluida.
7. Testar contra uma copia anonimizada do banco e backup restauravel, nunca diretamente em producao.
8. Nao alterar `main` nem publicar instalador R20 ate que os testes acima passem.

## Estado atual

Esta branch de desenvolvimento possui filtro conservador para residuos e uma trava explicita para `--experimental-fragments --apply`. Nenhum teste automatizado completo foi executado ou aprovado; esta documentacao nao representa liberacao de producao.
