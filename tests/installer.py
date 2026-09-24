"""Testa instalacao e falhas em uma pasta temporaria, sem tocar /root real."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1] / 'instalar_mkauth_acento.sh'
bash = os.environ.get('TEST_BASH') or shutil.which('bash')
assert bash, 'Bash nao encontrado'
text = source.read_text(encoding='utf-8')
php = text.split("<<'MKAUTH_PHP'\n", 1)[1].split('\nMKAUTH_PHP\n', 1)[0]
menu = text.split("<<'MKAUTH_MENU'\n", 1)[1].split('\nMKAUTH_MENU\n', 1)[0]
assert '$MAX_CAMADAS = 16;' in php
assert '$BEAM_WIDTH = 6;' in php
assert '$TOLERANCIA = 120;' in php
assert '$MAX_SEM_MELHORA = 4;' in php
assert "'2026.09.24-UNIVERSAL-HEX-R19'" in php
assert '\r' not in text

with tempfile.TemporaryDirectory(prefix='mkauth-test-') as tmp:
    base = Path(tmp)
    root = base / 'root'
    sbin = base / 'sbin'
    fake = base / 'bin'
    for directory in (root, sbin, fake):
        directory.mkdir()
    transformed = text.replace('/root', root.as_posix()).replace('/usr/local/sbin', sbin.as_posix())
    installer = base / 'install.sh'
    installer.write_text(transformed, encoding='utf-8', newline='\n')
    (base / 'menu.sh').write_text(menu, encoding='utf-8', newline='\n')
    stubs = {
        'id': '#!/bin/bash\necho 0\n',
        'php': '''#!/bin/bash
case "$1" in
    -r) exit 0 ;;
    -l) [ "${FAIL_LINT:-0}" != 1 ] ;;
    *) echo "TESTE: corretor nao pode ser executado na instalacao" >&2; exit 99 ;;
esac
''',
        'cp': '''#!/bin/bash
if [ "${FAIL_BACKUP:-0}" = 1 ]; then exit 1; fi
/usr/bin/cp "$@"
''',
    }
    for name, contents in stubs.items():
        p = fake / name
        p.write_text(contents, encoding='utf-8', newline='\n')
        p.chmod(0o755)
    def run(flags=None):
        env = os.environ.copy()
        env.update(flags or {})
        return subprocess.run([bash, '-c', 'export PATH="$(cygpath -u "$1" 2>/dev/null || printf %s "$1"):$PATH"; bash "$2"',
                               'test', fake.as_posix(), installer.as_posix()],
                              env=env, text=True, capture_output=True)
    for script in (installer, base / 'menu.sh'):
        subprocess.run([bash, '-n', str(script)], check=True)
    corrector = root / 'mkauth_corrige_acentos.php'
    target_menu = sbin / 'mkauth-acento'
    corrector.write_text('CORRETOR ANTERIOR', encoding='utf-8')
    target_menu.write_text('MENU ANTERIOR', encoding='utf-8')
    for flags in ({'FAIL_LINT': '1'}, {'FAIL_BACKUP': '1'}):
        result = run(flags)
        assert result.returncode != 0, result.stdout + result.stderr
        assert corrector.read_text() == 'CORRETOR ANTERIOR'
        assert target_menu.read_text() == 'MENU ANTERIOR'
    result = run()
    assert result.returncode == 0, result.stdout + result.stderr
    expected_php = php.replace('/root', root.as_posix()).replace('/usr/local/sbin', sbin.as_posix())
    expected_menu = menu.replace('/root', root.as_posix()).replace('/usr/local/sbin', sbin.as_posix())
    assert corrector.read_text(encoding='utf-8').rstrip() == expected_php.rstrip()
    assert target_menu.read_text(encoding='utf-8').rstrip() == expected_menu.rstrip()
    assert any(p.read_text() == 'CORRETOR ANTERIOR' for p in root.glob('*.bkp-*'))
    assert any(p.read_text() == 'MENU ANTERIOR' for p in sbin.glob('*.bkp-*'))
    assert not list(root.glob('.mkauth-acento-install.*'))
    # Exercita as opcoes reais do menu com PHP simulado, sem banco.
    (fake / 'php').write_text('#!/bin/bash\ncase "$1" in\n-r) exit 0 ;;\n-v) echo \'PHP simulado\'; exit 0 ;;\nesac\nprintf \'%s\\n\' "$*" >> "$MENU_CALLS"\n', encoding='utf-8', newline='\n')
    (fake / 'clear').write_text('#!/bin/bash\nexit 0\n', encoding='utf-8')
    (fake / 'clear').chmod(0o755)
    calls = base / 'calls.txt'
    for inputs, expected in [('1\n\n0\n', ''), ('10\n\n0\n', '--experimental-fragments'),
                              ('11\nCANCELAR\n0\n', None),
                              ('11\nAPLICAR EXPERIMENTAL\n\n0\n', '--experimental-fragments --apply')]:
        calls.write_text('')
        env = os.environ.copy(); env['MENU_CALLS'] = calls.as_posix()
        r = subprocess.run([bash, '-c', 'export PATH="$(cygpath -u "$1" 2>/dev/null || printf %s "$1"):$PATH"; bash "$2"',
                            'menu', fake.as_posix(), target_menu.as_posix()], input=inputs.encode(),
                           env=env, capture_output=True, timeout=20)
        assert r.returncode == 0, r.stdout + r.stderr
        lines = calls.read_text().splitlines()
        if expected is None: assert not lines
        else:
            assert len(lines) == 1, (expected, lines, r.stdout, r.stderr)
            assert lines[0].endswith('mkauth_corrige_acentos.php' + (' ' + expected if expected else ''))
print('OK: sintaxe Bash, parametros R19, falha de lint, falha de backup, instalacao e backups.')
