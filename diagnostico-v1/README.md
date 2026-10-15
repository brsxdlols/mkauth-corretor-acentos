# Diagnóstico independente de acentuação — v1.0.0

Este diretório contém um **instalador separado e somente leitura**, para triagem inicial em outros servidores MK-AUTH. Não substitui nem modifica o corretor R19 existente no repositório.

## Instalação

Como root no servidor:

```bash
curl -fL https://raw.githubusercontent.com/brsxdlols/mkauth-corretor-acentos/main/diagnostico-v1/mkauth-acento-diagnostico-instalar.sh -o /root/mkauth-acento-diagnostico-instalar.sh
bash -n /root/mkauth-acento-diagnostico-instalar.sh
bash /root/mkauth-acento-diagnostico-instalar.sh
mkauth-acento-diagnostico --run
```

Requisitos: Bash, Python 3, cliente `mysql`, acesso local ao banco `mkradius` e arquivo `/etc/mysql/debian.cnf` funcional.

## Segurança e limitações

- Executa apenas consultas SELECT e grava relatório TSV em `/var/log/mkauth-acento-diagnostico` (permissões restritas).
- Não executa UPDATE, DELETE, ALTER nem correção automática.
- Identifica **possíveis** sequências de mojibake e perda de caracteres; os indicadores podem gerar falsos positivos.
- Exige chave primária numérica simples; examina até 100.000 linhas por execução, com aviso quando o limite é atingido.
- O relatório inclui HEX original potencialmente sensível: não publique dados de clientes.
- Caracteres perdidos exigem evidência histórica independente; não são reconstruídos por adivinhação.
- Para qualquer correção posterior, criar backup, plano individualizado, validação por HEX e transação com rollback.

Esta versão é para diagnóstico inicial; ainda requer teste operacional no servidor de destino.
