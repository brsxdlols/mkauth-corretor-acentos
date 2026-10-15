#!/usr/bin/env bash
set -Eeuo pipefail
# MK-AUTH - auditoria de acentuacao (somente leitura) v1.0.0
# Instalador independente; nao substitui o corretor R19.
VERSION="1.0.0-diagnostico"
TARGET="/usr/local/sbin/mkauth-acento-diagnostico"
if [[ "${1:-}" == "--version" ]]; then echo "$VERSION"; exit 0; fi
if [[ "${1:-}" != "--run" ]]; then
  [[ "$EUID" -eq 0 ]] || { echo "Execute como root" >&2; exit 1; }
  command -v python3 >/dev/null || { echo "python3 ausente" >&2; exit 1; }
  command -v mysql >/dev/null || { echo "mysql ausente" >&2; exit 1; }
  install -d -m 0700 /var/log/mkauth-acento-diagnostico /var/backups/mkauth-acento-diagnostico
  if [[ -e "$TARGET" ]]; then
    cp -p "$TARGET" "/var/backups/mkauth-acento-diagnostico/anterior-$(date +%Y%m%d-%H%M%S)"
  fi
  install -m 0750 "$(readlink -f "$0")" "$TARGET"
  echo "Instalado: $TARGET"
  echo "Execute: mkauth-acento-diagnostico --run"
  echo "Somente leitura; o R19 existente nao foi modificado."
  exit 0
fi
[[ "$EUID" -eq 0 ]] || { echo "Execute como root" >&2; exit 1; }
exec python3 - <<'PY'
import csv,datetime,hashlib,os,pathlib,re,subprocess
DB="mkradius"
CONF="/etc/mysql/debian.cnf"
OUT=pathlib.Path("/var/log/mkauth-acento-diagnostico")
LOST=bytes.fromhex("C383C2AFC382C2BFC382C2BD")
def sql(query):
    r=subprocess.run(["mysql","--defaults-file="+CONF,"--default-character-set=utf8mb4","--batch","--raw","--skip-column-names",DB,"-e",query],capture_output=True,text=True,timeout=180)
    if r.returncode: raise RuntimeError(r.stderr.strip())
    return [line.split("\t") for line in r.stdout.splitlines()]
def qi(name):
    if not re.fullmatch(r"[A-Za-z0-9_]+",name): raise ValueError("Identificador invalido")
    return "`"+name+"`"
def check():
    if not pathlib.Path(CONF).is_file(): raise RuntimeError("Credenciais nao encontradas: "+CONF)
    print("Banco:",sql("SELECT DATABASE(),VERSION()")[0])
def diagnose():
    tables=[r[0] for r in sql("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE'")]
    table=input("Tabela [sis_logs]: ").strip() or "sis_logs"
    if table not in tables: raise ValueError("Tabela nao encontrada")
    cols=sql("SELECT COLUMN_NAME,DATA_TYPE,COLUMN_KEY,CHARACTER_SET_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='"+table+"'")
    textcols=[c for c in cols if c[1].lower() in ("char","varchar","tinytext","text","mediumtext","longtext")]
    print("Campos:",", ".join(c[0] for c in textcols))
    col=input("Campo [registro]: ").strip() or "registro"
    if col not in [c[0] for c in textcols]: raise ValueError("Campo invalido")
    pk=[c for c in cols if c[2]=="PRI"]
    if len(pk)!=1 or pk[0][1].lower() not in ("tinyint","smallint","mediumint","int","integer","bigint"): raise ValueError("Requer chave primaria numerica simples")
    limit=int(input("Limite de linhas [10000]: ").strip() or "10000")
    if not 1<=limit<=100000: raise ValueError("Limite de 1 a 100000")
    rows=sql("SELECT "+qi(pk[0][0])+",HEX("+qi(col)+") FROM "+qi(table)+" WHERE "+qi(col)+" IS NOT NULL ORDER BY "+qi(pk[0][0])+" LIMIT "+str(limit))
    OUT.mkdir(mode=0o700,parents=True,exist_ok=True)
    os.chmod(OUT,0o700)
    path=OUT/("analise-"+table+"-"+col+"-"+datetime.datetime.now().strftime("%Y%m%d-%H%M%S")+".tsv")
    count=0
    with path.open("w",newline="",encoding="utf-8") as f:
        os.chmod(path,0o600)
        writer=csv.writer(f,delimiter="\t")
        writer.writerow(["id","classificacao","hex_original"])
        for key,h in rows:
            raw=bytes.fromhex(h)
            tags=[]
            if LOST in raw: tags.append("PERDA_CARACTERE_EXIGE_HISTORICO")
            if b"\xef\xbf\xbd" in raw: tags.append("UTF8_REPLACEMENT_LITERAL")
            if b"\xc3\x83\xc2" in raw or b"\xc3\x82\xc2" in raw: tags.append("MOJIBAKE_MULTIPLO_POSSIVEL")
            if re.search(rb"\xc3[\x80-\xbf]",raw): tags.append("UTF8_EM_LATIN1_POSSIVEL")
            if tags:
                writer.writerow([key,",".join(tags),h]); count+=1
    print("Linhas analisadas:",len(rows),"| Sinalizadas:",count)
    print("Relatorio:",path)
    print("SHA256:",hashlib.sha256(path.read_bytes()).hexdigest())
    if len(rows)==limit: print("ATENCAO: limite atingido; analise parcial.")
    print("Indicadores podem ter falsos positivos. Nenhum UPDATE executado.")
while True:
    print("\n=== MK-AUTH DIAGNOSTICO DE ACENTOS v1.0.0 ===")
    print("1 - Testar banco\n2 - Analisar tabela/campo (somente leitura)\n0 - Sair")
    try:
        choice=input("Opcao: ").strip()
        if choice=="0": break
        if choice=="1": check()
        elif choice=="2": check(); diagnose()
        else: print("Opcao invalida")
    except (ValueError,RuntimeError,subprocess.TimeoutExpired,KeyboardInterrupt,EOFError) as e:
        print("ERRO:",e)
PY
