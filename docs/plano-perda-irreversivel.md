# Plano de proteção contra perda irreversível — revisão após R19

Esta proposta não altera o instalador de produção e não contém dados reais de clientes.

## Evidência técnica sintética

- Um campo `LONGTEXT latin1` pode armazenar bytes `EF BF BD` (U+FFFD codificado em UTF-8), mesmo que a coluna declare latin1.
- A sequência textual `ï¿½` pode resultar da interpretação de `EF BF BD` como Latin1; recodificações adicionais geram `Ã¯Â¿Â½` e `ÃƒÂ¯Ã‚Â¿Ã‚Â½`.
- Reverter essas camadas pode terminar em `�`; isso **não** recupera o caractere original.
- `ÇÃ` em uma coluna latin1 pode ser perfeitamente válido. Um marcador suspeito isolado não prova corrupção.
- Uma contagem sobre um INSERT estendido do mysqldump não representa necessariamente um único registro. Para recuperação, interpretar corretamente a serialização SQL, sem dividir por ocorrências textuais de `(22,`.

## Requisitos de segurança

1. Na análise, identificar U+FFFD e suas formas conhecidas de mojibake sem presumir reversibilidade; contabilizar ocorrências por registro, quando a chave for confiável.
2. Classificar perdas comprovadas como `IRRECUPERAVEL`, sem sugerir reconstrução por ortografia ou por documento semelhante.
3. Bloquear `--apply` para candidatos que contenham marcadores de perda, inclusive no modo `--experimental-fragments`.
4. Preservar campos válidos em Latin1 e não converter tabelas ou colunas em massa.
5. Manter a confirmação humana, backups, HEX original e auditoria já existentes; falhar fechado se a análise ou backup falhar.
6. Não imprimir texto jurídico integral em logs públicos ou testes; usar exclusivamente dados sintéticos.
7. Não modificar o comando `mkauth-acento` nem as opções 1–4 e 10–11.
8. Validar o corretor PHP, Bash e os testes existentes antes de preparar um instalador de release.

## Casos sintéticos de regressão

| Entrada | Esperado |
| --- | --- |
| `PRESTAÇÃO` | Preservado |
| `PRESTA��O` | Irrecuperável; nenhum UPDATE |
| `PRESTAï¿½ï¿½O` | Irrecuperável; nenhum UPDATE |
| `PRESTAÃ¯Â¿Â½Ã¯Â¿Â½O` | Irrecuperável; nenhum UPDATE |
| `PRESTAÃƒÂ¯Ã‚Â¿Ã‚Â½ÃƒÂ¯Ã‚Â¿Ã‚Â½O` | Irrecuperável; nenhum UPDATE |
| `SERVIÃ‡O` | Candidato somente se reversão exata, heurística e revisão aprovarem |
| `TERMO DE ADESÃO` | Preservado |

**Estado:** plano de implementação. Não afirmar que o bloqueio ou os testes novos estão implementados até alterar o código e executá-los.
