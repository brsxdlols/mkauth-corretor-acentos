# MK-AUTH — corretor de acentuação R16

Instalador único `instalar_mkauth_acento.sh`, com corretor PHP e menu `mkauth-acento` embutidos. Não precisa de patch Python. A instalação **não executa o corretor**.

Versão do algoritmo: `2026.08.17-UNIVERSAL-HEX-R16`. Empacotamento: **1**.

O algoritmo tenta desfazer recodificações completas entre UTF-8, ISO-8859-1 e Windows-1252. Limites: **16 camadas**, `BEAM_WIDTH=6`, `TOLERANCIA=120`, `MAX_SEM_MELHORA=4`.

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

## Limites e evolução

Não existe garantia de recuperação de 100% dos textos nem de ausência de falsos positivos. Score zero é uma heurística, não uma prova do nome original. Uma sequência que parece mojibake pode ter sido digitada literalmente. Truncamentos e bytes perdidos não podem ser preenchidos por suposição.

**A recuperação híbrida experimental não está incluída.** Textos que misturam trechos corretos e recodificados podem permanecer suspeitos, como `3Âª Travessa João Exemplo`. Essa limitação é intencional nesta versão.

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

Veja [CHANGELOG.md](CHANGELOG.md) para diferenças em relação à R16 instalada anteriormente.
