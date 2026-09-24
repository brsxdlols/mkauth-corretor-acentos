# MK-AUTH — corretor de acentuação R19

Instalador único `instalar_mkauth_acento.sh`, com corretor PHP e menu `mkauth-acento` embutidos. Não precisa de patch Python. A instalação **não executa o corretor**.

Versão do algoritmo: `2026.09.24-UNIVERSAL-HEX-R19`.

O algoritmo tenta desfazer recodificações completas entre UTF-8, ISO-8859-1 e Windows-1252. A R17 acrescenta o perfil explícito `WINDOWS-1252-PRESERVE-C1`: os cinco bytes indefinidos `81`, `8D`, `8F`, `90` e `9D` são representados pelos controles Unicode correspondentes. A representação é bijetiva e cada camada precisa reconstruir exatamente a entrada; não se usam descarte de bytes ou transliteração. Limites: **16 camadas**, `BEAM_WIDTH=6`, `TOLERANCIA=120`, `MAX_SEM_MELHORA=4`.

## Instalar e analisar

Em um MK-AUTH Linux, como root:

```bash
curl --fail --location \
  https://raw.githubusercontent.com/brsxdlols/mkauth-corretor-acentos/main/instalar_mkauth_acento.sh \
  --output /root/instalar_mkauth_acento.sh
bash -n /root/instalar_mkauth_acento.sh
bash /root/instalar_mkauth_acento.sh
mkauth-acento
```

Escolha **1 — Somente analisar**. Revise o resumo completo e **todos** os `CORRIGIVEL`. A prévia no log limita o tamanho do texto; os candidatos completos são gravados em `/root/mkauth_acento_*.jsonl`.

O instalador exige PHP CLI 7/8 com `mysqli` e `iconv`, Bash e utilitários Linux. O PHP é detectado novamente a cada abertura do menu. A compatibilidade PHP é verificada pela matriz de testes; a análise real inicial foi executada com PHP 8.0.30. MySQL/MariaDB precisam oferecer `utf8mb4`.

A configuração embutida mantém os padrões do instalador anterior: banco `mkradius`, usuário MySQL `root`, senha de fábrica `vertrigo`, TCP local `127.0.0.1:3306`, seguido de sockets locais. Se a instalação usa outra configuração, ajuste o bloco **CONFIGURACAO** antes de instalar. Não publique credenciais reais.

## Aplicar somente depois da revisão

As opções **2** e **4** pedem confirmação textual. `--apply` também existe para uso explícito via CLI. A aplicação faz uma nova análise; portanto, revise novamente se os dados ou o programa mudaram. Este empacotamento não vincula uma aprovação a um manifesto imutável.

Antes dos UPDATEs, o corretor grava os candidatos completos e cria um dump das tabelas que serão afetadas. Falhas na leitura, auditoria ou backup interrompem a execução. O backup exige `mysqldump`; confirme previamente que consegue restaurar um dump no seu ambiente.

Cada UPDATE exige a chave do registro e o `HEX()` original do campo. Se os bytes mudaram desde a análise daquela execução, o campo não é alterado. O modo SQL estrito evita substituições silenciosas ao escrever em uma coluna cujo charset não suporta o resultado.

Não há transação global: falhas durante a aplicação podem deixar parte dos campos já corrigida. O log, a auditoria e o backup permitem investigar esse estado. Não execute corretores simultaneamente. Os arquivos contêm dados pessoais e devem permanecer privados.

## O que é preservado

| Classificação | Comportamento |
|---|---|
| `OK` | Texto preservado |
| `CORRIGIVEL` | Candidato com score zero e conversão reversível; exige revisão humana antes da aplicação |
| `PARCIAL` | Mostra a melhor tentativa, mas mantém o valor original no banco |
| `SUSPEITO` | Mantém o original |
| `IRRECUPERAVEL` | Marcador de perda detectado; mantém o original |
| `SEM CHAVE` | Coluna não examinada por falta de identificação segura de linha |

Só são aceitas chaves PRIMARY/UNIQUE de colunas completas e NOT NULL. O fallback antigo de chaves manuais foi removido; não se deve inventar uma chave para tabelas como `radusergroup`.

Os históricos `sis_enviadas`, `sis_logs`, `sis_ativ`, `sis_gnettits` e `sis_msg` ficam fora por padrão. Outros históricos/addons podem ter nomes diferentes e aparecer na análise. A opção 3 inclui os históricos excluídos e pode ser demorada.

O escopo herdado descobre colunas de texto de todas as tabelas elegíveis; isso pode incluir identificadores e conteúdo de addons. Revise o significado de cada campo: um resultado ortograficamente plausível não garante que seja adequado para um login, token, modelo de documento ou outro campo técnico.

## Recuperação experimental por trechos (R19)

A R19 inclui a técnica adicional como opção explícita. As opções 1–4 mantêm o comportamento anterior. No menu, use **10 — Analisar com recuperação experimental por trechos**; revise TODOS os candidatos e o JSONL completo; só depois use **11 — Aplicar com recuperação experimental por trechos**. A opção 11 exige digitar `APLICAR EXPERIMENTAL`.

Na CLI, a análise usa `php /root/mkauth_corrige_acentos.php --experimental-fragments`. Adicionar `--apply` aplica os candidatos após nova análise, com as mesmas salvaguardas e limitações de backup do modo padrão. Não existe aprovação vinculada a um manifesto imutável nessa CLI.

O modo adicional tenta reverter sequências UTF-8 completas dentro dos trechos corrompidos, somente quando o método padrão preservaria o campo. Exige convergência dos passes explorados, score zero, preservação de ASCII e tags HTML, e conversões individuais com ida e volta exata. A auditoria registra a rota `EXPERIMENTAL-FRAGMENTOS` e `prova_fragmentos` com offsets em bytes relativos à entrada de cada rodada. Mantém letras maiúsculas/minúsculas; não deduz grafias de nomes, cidades ou caracteres perdidos.

Limites adicionais: 16 rodadas, 200 estados, 256 KiB por campo e 64 MiB de processamento acumulado. Se houver divergência, limite excedido, alteração de tag HTML ou marcador de perda, mantém o resultado do método padrão. Alguns truncamentos não são identificáveis com certeza; reversibilidade não prova a intenção original. A revisão continua obrigatória, sobretudo em nomes, documentos e campos técnicos. A busca explora passes por perfil, não todas as segmentações possíveis.

A implementação reproduziu em teste privado as cinco recuperações previamente revisadas. Os testes públicos usam somente textos sintéticos; nenhum dado pessoal ou substituição específica de cadastro faz parte do instalador.

## Limites e evolução

Não existe garantia de recuperação de 100% dos textos nem de ausência de falsos positivos. Score zero é uma heurística, não uma prova do nome original. Uma sequência que parece mojibake pode ter sido digitada literalmente. Truncamentos e bytes perdidos não podem ser preenchidos por suposição.

**O modo padrão mantém a recuperação por trechos desativada.** A R18 acrescenta somente uma regra restrita para ordinal feminino no início de endereço simples: por exemplo, `3Âª Travessa João Exemplo` → `3ª Travessa João Exemplo`. Aceita números de 1 a 999, seguidos de Travessa, Rua, Avenida ou Alameda, com essa capitalização. Preserva o restante byte a byte; exige reconstrução exata e score final zero. HTML, quebras de linha, outros contextos e sufixos com `Ã`/`Â` não recebem essa regra adicional. A conversão integral existente permanece disponível nesses casos.

A rota aparece na auditoria como `ORDINAL-ENDERECO-INICIAL:ISO-8859-1`. Ela continua exigindo revisão humana: o contexto textual não prova por si só que a sequência não foi digitada literalmente. Não há dicionário de cidades ou nomes, e as correções documentais específicas dos servidores permanecem privadas.

Referências de chamados, mensagens e cadastros podem ajudar uma restauração individual, mas devem ficar em uma base privada com tabela, campo, identificador, data e conflitos. Login pode ser reutilizado e nome pode mudar; uma referência única também exige revisão. Nunca transforme uma associação de cliente em uma substituição universal de nomes.

Para adicionar casos de outros servidores:

1. Rode somente análise e guarde o relatório completo e os bytes originais em ambiente privado.
2. Separe recodificação reversível, mistura de encodings e perda/truncamento.
3. Crie um caso sintético equivalente em `tests/run.php`, incluindo o texto correto que deve permanecer intacto.
4. Rode todos os testes e compare a análise antes/depois. Técnicas experimentais continuam separadas até validação.
5. Revise os novos candidatos antes de aplicar em qualquer servidor.

## Testes

```bash
php tests/run.php
python3 tests/installer.py
```

Os testes PHP carregam somente as funções, sem abrir conexão com banco. O teste do instalador usa diretórios temporários e simula PHP para verificar falhas de lint/backup, backups anteriores e instalação; a sintaxe PHP real é verificada separadamente no CI.

Veja [CHANGELOG.md](CHANGELOG.md) para as diferenças entre versões.
