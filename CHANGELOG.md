# Alterações

## R19 — 2026.09.24

- Recuperação experimental por trechos disponível somente com `--experimental-fragments` ou opções 10/11 do menu. Desativada por padrão.
- Conversões reversíveis, convergência entre passes, preservação de ASCII e tags HTML, limites de execução e prova dos segmentos na auditoria.
- 533 testes PHP, mais testes de instalação e das opções do menu; nenhum dado de cliente nos testes públicos.
- Sem dicionários de nomes/cidades ou normalização de caixa. A revisão dos candidatos continua necessária.

## R18 — 2026.09.24

- Regra restrita e reversível para ordinal feminino corrompido no início de endereço simples, preservando o restante do campo. Não implementa recuperação genérica por fragmentos.
- Apenas números de 1 a 999 e contextos Travessa, Rua, Avenida e Alameda; exige score final zero e revisão dos candidatos.
- 461 testes, incluindo limites de contexto, HTML, idempotência e preservação do comportamento integral anterior.
- Nenhuma substituição específica de cidade, nome ou cliente incorporada.

## R17 — 2026.09.24

- Nova rota integral e reversível `WINDOWS-1252-PRESERVE-C1`, preservando os cinco bytes indefinidos do CP1252 como controles Unicode correspondentes. Todos os 256 valores têm teste de ida e volta.
- Corrigida a detecção de prefixos `Ã`/`Â` seguidos de símbolos CP1252, evitando encerrar a busca em um falso score zero, como em `Ã“`.
- 400 testes: casos anteriores, cobertura dos 256 bytes, letras maiúsculas acentuadas, até 16 camadas, rejeição de truncamento e preservação de textos multilíngues.
- Sem dicionário de nomes, sem preenchimento de texto perdido e sem recuperação híbrida por trechos.

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
