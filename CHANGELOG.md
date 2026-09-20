# Alterações

## R16 — empacotamento 1

- Instalador único com corretor e menu, sem executar o programa ao instalar.
- Identificação corrigida para `2026.08.17-UNIVERSAL-HEX-R16`.
- Mantidos 16 camadas, beam 6, tolerância 120 e limite de 4 camadas sem melhora.
- Contador de progresso compara com o melhor score **antes** da camada. Antes, o score já havia sido atualizado e o contador crescia mesmo quando havia melhora, interrompendo casos na oitava camada.
- Cada conversão exige reprodução exata do texto de entrada ao reverter a operação.
- Auditoria JSONL dos candidatos completos e dos campos corrigidos; falha de gravação interrompe a execução.
- Relatórios e backups privados, nomes com PID para evitar colisões no mesmo segundo.
- Erros de SELECT bloqueiam aplicação; falhas fatais retornam código diferente de zero.
- Apenas PRIMARY/UNIQUE completas e NOT NULL; removida confiança em chaves manuais não garantidas pelo banco.
- Escrita com `STRICT_ALL_TABLES`.
- PHP e menu validados em diretório temporário antes da substituição; falha de backup aborta instalação.
- Nenhuma técnica híbrida experimental ou tabela de nomes reais incorporada.

Os 15 testes sintéticos de 9, 12 e 16 camadas que falharam na cópia anterior passaram com o ajuste de progresso. A análise inicial na base de referência continuou sem candidatos automáticos; não foi executado `--apply`.
