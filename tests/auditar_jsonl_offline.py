#!/usr/bin/env python3
"""Auditoria OFFLINE de JSONL R19: nenhuma conexao SQL, nenhuma escrita no banco."""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

RESIDUOS = re.compile(r"[ÃÂÆ]|â€|â‚|ï¿½|\ufffd|[\u0080-\u009f\u00ad]")
TAGS = re.compile(r"<[^>]*>")
ASCII = re.compile(r"[^\x00-\x7f]")

def prova_valida(reg):
    texto = reg.get("antes")
    provas = reg.get("prova_fragmentos")
    if not isinstance(texto, str) or not isinstance(provas, list) or not provas:
        return False, "prova_ausente"
    for passo in provas:
        edicoes = passo.get("edicoes") if isinstance(passo, dict) else None
        if not isinstance(edicoes, list) or not edicoes:
            return False, "edicoes_ausentes"
        partes = []
        pos = 0
        bruto = texto.encode("utf-8")
        for e in edicoes:
            try:
                off = e["offset_bytes"]
                antes = e["antes"].encode("utf-8")
                depois = e["depois"].encode("utf-8")
            except (KeyError, AttributeError, UnicodeError):
                return False, "edicao_invalida"
            if not isinstance(off, int) or off < pos or off + len(antes) > len(bruto):
                return False, "offset_invalido"
            if bruto[off:off + len(antes)] != antes:
                return False, "fragmento_nao_confere"
            partes.extend((bruto[pos:off], depois))
            pos = off + len(antes)
        partes.append(bruto[pos:])
        try:
            texto = b"".join(partes).decode("utf-8")
        except UnicodeError:
            return False, "utf8_invalido"
    if texto != reg.get("depois"):
        return False, "destino_divergente"
    return True, "ok"

def classificar(reg):
    if reg.get("evento") != "CANDIDATO":
        return "outro_evento"
    ok, motivo = prova_valida(reg)
    if not ok:
        return "prova_falha_" + motivo
    antes, depois = reg["antes"], reg["depois"]
    if ASCII.sub("", antes) != ASCII.sub("", depois):
        return "ascii_alterado"
    if TAGS.findall(antes) != TAGS.findall(depois):
        return "html_alterado"
    if RESIDUOS.search(depois):
        return "residuos"
    if RESIDUOS.search(antes) is None:
        return "sem_evidencia_mojibake"
    return "revisao_manual"

def executar(arquivo):
    cont = collections.Counter()
    n = 0
    with open(arquivo, "r", encoding="utf-8") as fh:
        for linha, dado in enumerate(fh, 1):
            if not dado.strip():
                continue
            n += 1
            try:
                reg = json.loads(dado)
                classe = classificar(reg)
            except (ValueError, TypeError, KeyError, UnicodeError):
                classe = "registro_invalido"
            cont[classe] += 1
    print("AUDITORIA OFFLINE (somente leitura)")
    print("Registros:", n)
    for classe, total in sorted(cont.items()):
        print("%s: %d" % (classe, total))
    print("APLICACOES AUTOMATICAS AUTORIZADAS: 0")
    return 0 if n and not any(k.startswith("prova_falha_") or k == "registro_invalido" for k in cont) else 2

def autoteste():
    origem = "SÃ£o"
    reg = {"evento": "CANDIDATO", "antes": origem, "depois": "São",
           "prova_fragmentos": [{"encoding": "ISO-8859-1",
               "edicoes": [{"offset_bytes": 1, "antes": "Ã£", "depois": "ã"}]}]}
    assert classificar(reg) == "revisao_manual"
    assert classificar(dict(reg, depois="SÃ£o")) == "prova_falha_destino_divergente"
    ruim = dict(reg, prova_fragmentos=[{"edicoes": [{"offset_bytes": 2, "antes": "Ã£", "depois": "ã"}]}])
    assert classificar(ruim) == "prova_falha_fragmento_nao_confere"
    assert classificar(dict(reg, depois="São!", prova_fragmentos=[
        {"edicoes": [{"offset_bytes": 1, "antes": "Ã£", "depois": "ã!"}]}])) == "ascii_alterado"
    assert classificar(dict(reg, depois="SÃ£o", prova_fragmentos=[
        {"edicoes": [{"offset_bytes": 1, "antes": "Ã£", "depois": "Ã£"}]}])) == "residuos"
    print("AUTOTESTE OK: 5 verificacoes")
    return 0

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("jsonl", nargs="?", type=Path)
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        sys.exit(autoteste())
    if args.jsonl is None:
        p.error("informe o caminho do JSONL")
    sys.exit(executar(args.jsonl))
