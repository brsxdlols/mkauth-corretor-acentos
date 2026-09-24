#!/bin/bash
# MK-AUTH - instalador unico. Nao executa analise nem UPDATE na instalacao.
set -euo pipefail
umask 077
VERSAO="2026.09.24-UNIVERSAL-HEX-R17"
CORRETOR="/root/mkauth_corrige_acentos.php"
MENU="/usr/local/sbin/mkauth-acento"
if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: execute como root." >&2
    exit 1
fi
detectar_php()
{
    CANDIDATOS=""

    # PHP padrao do sistema primeiro.
    if command -v php >/dev/null 2>&1; then
        CANDIDATOS="$(command -v php)"
    fi

    # Depois nomes explicitos.
    for CAND in \
        php8.5 php8.4 php8.3 php8.2 php8.1 php8.0 \
        php7.4 php7.3 php7.2 php7.1 php7.0
    do

        if command -v "$CAND" >/dev/null 2>&1; then

            BIN="$(command -v "$CAND")"

            JA_EXISTE=0

            for EXISTENTE in $CANDIDATOS
            do
                if [ "$EXISTENTE" = "$BIN" ]; then
                    JA_EXISTE=1
                    break
                fi
            done

            if [ "$JA_EXISTE" -eq 0 ]; then
                CANDIDATOS="$CANDIDATOS $BIN"
            fi
        fi
    done


    # Escolhe o primeiro PHP 7/8 com mysqli e iconv.
    for BIN in $CANDIDATOS
    do

        if "$BIN" -r '
            $v = PHP_VERSION_ID;

            if ($v < 70000) {
                exit(1);
            }

            if (!extension_loaded("mysqli")) {
                exit(1);
            }

            if (!extension_loaded("iconv")) {
                exit(1);
            }

            exit(0);
        ' >/dev/null 2>&1
        then
            echo "$BIN"
            return 0
        fi
    done

    return 1
}

PHP_BIN="$(detectar_php)" || { echo "ERRO: PHP 7/8 com mysqli e iconv nao encontrado." >&2; exit 1; }
STAGE="$(mktemp -d /root/.mkauth-acento-install.XXXXXXXX)"
trap 'rm -rf -- "$STAGE"' EXIT
cat > "$STAGE/corretor.php" <<'MKAUTH_PHP'
<?php

/*
 * ============================================================
 * MK-AUTH - CORRETOR UNIVERSAL DE ACENTUACAO
 * ============================================================
 *
 * MODO ANALISE:
 *
 *   php mkauth_corrige_acentos.php
 *
 * MODO CORRECAO:
 *
 *   php mkauth_corrige_acentos.php --apply
 *
 * ANALISE COM HISTORICO:
 *
 *   php mkauth_corrige_acentos.php --include-history
 *
 * CORRECAO COM HISTORICO:
 *
 *   php mkauth_corrige_acentos.php --apply --include-history
 *
 * ============================================================
 */

error_reporting(E_ALL);
ini_set('display_errors', '1');
ini_set('memory_limit', '-1');

set_time_limit(0);
umask(0077);


/*
 * ============================================================
 * CONFIGURACAO
 * ============================================================
 */

$VERSAO = '2026.09.24-UNIVERSAL-HEX-R17';

$DB_USER = 'root';
$DB_PASS = 'vertrigo';
$DB_NAME = 'mkradius';

$APPLY =
    in_array(
        '--apply',
        $argv,
        true
    );

$INCLUDE_HISTORY =
    in_array(
        '--include-history',
        $argv,
        true
    );

$MAX_CAMADAS = 16;

$TS = date('Ymd-His') . '-' . getmypid();
$OUTPUT_DIR = getenv('MKAUTH_OUTPUT_DIR') ?: '/root';
if (!is_dir($OUTPUT_DIR) || !is_writable($OUTPUT_DIR)) {
    fwrite(STDERR, "ERRO: diretorio de relatorios indisponivel.\n");
    exit(1);
}
$AUDITORIA = $OUTPUT_DIR . '/mkauth_acento_' . $TS . '.jsonl';

$LOG =
    $OUTPUT_DIR . '/mkauth_acento_' .
    $TS .
    '.log';

$IRRECUPERAVEIS =
    $OUTPUT_DIR . '/mkauth_acento_irrecuperaveis_' .
    $TS .
    '.txt';


/*
 * ============================================================
 * HISTORICOS IGNORADOS POR PADRAO
 * ============================================================
 */

$IGNORAR = array(

    'sis_enviadas',

    'sis_logs',

    'sis_ativ',

    'sis_gnettits',

    'sis_msg'
);


/*
 * ============================================================
 * FUNCOES
 * ============================================================
 */

function logmsg($msg)
{
    global $LOG;

    echo
        $msg .
        PHP_EOL;

    if (file_put_contents($LOG, $msg . PHP_EOL, FILE_APPEND | LOCK_EX) === false) {
        fwrite(STDERR, "ERRO: falha ao gravar relatorio; execucao interrompida.\n");
        exit(1);
    }
}


function auditar($registro)
{
    global $AUDITORIA;
    $json = json_encode($registro, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($AUDITORIA, $json . PHP_EOL, FILE_APPEND | LOCK_EX) === false) {
        fwrite(STDERR, "ERRO: falha na auditoria; execucao interrompida.\n");
        exit(1);
    }
}

function falhar($mensagem)
{
    fwrite(STDERR, $mensagem . PHP_EOL);
    exit(1);
}

function ident($nome)
{
    return
        '`' .
        str_replace(
            '`',
            '``',
            $nome
        ) .
        '`';
}


function valido_utf8($s)
{
    if ($s === null) {
        return false;
    }

    return
        preg_match(
            '//u',
            $s
        ) === 1;
}


function resumo($s, $limite = 300)
{
    $s =
        str_replace(
            array(
                "\r",
                "\n",
                "\t"
            ),
            array(
                ' ',
                ' ',
                ' '
            ),
            $s
        );


    if (
        function_exists(
            'mb_substr'
        )
    ) {

        return
            mb_substr(
                $s,
                0,
                $limite,
                'UTF-8'
            );
    }


    return
        substr(
            $s,
            0,
            $limite
        );
}


/*
 * ============================================================
 * EXECUTA UMA CAMADA DE REVERSAO
 * ============================================================
 */

// Perfil reversivel explicito: CP1252 com os cinco bytes indefinidos
// 81, 8D, 8F, 90 e 9D preservados como controles Unicode correspondentes.
// Nao mistura encodings por trecho, nao remove bytes e nao translitera.
function cp1252_c1_decode($bytes)
{
    $out = '';
    foreach (str_split($bytes) as $byte) {
        $n = ord($byte);
        if (in_array($n, array(0x81, 0x8D, 0x8F, 0x90, 0x9D), true)) {
            $out .= "\xC2" . $byte;
        } else {
            $c = @iconv('WINDOWS-1252', 'UTF-8', $byte);
            if ($c === false) return false;
            $out .= $c;
        }
    }
    return $out;
}

function cp1252_c1_encode($s)
{
    static $map = null;
    if (!valido_utf8($s)) return false;
    if ($map === null) {
        $map = array();
        for ($n = 0; $n < 256; $n++) {
            $c = cp1252_c1_decode(chr($n));
            if ($c === false || isset($map[$c])) return false;
            $map[$c] = chr($n);
        }
    }
    $chars = preg_split('//u', $s, -1, PREG_SPLIT_NO_EMPTY);
    if ($chars === false) return false;
    $bytes = '';
    foreach ($chars as $c) {
        if (!array_key_exists($c, $map)) return false;
        $bytes .= $map[$c];
    }
    if (cp1252_c1_decode($bytes) !== $s) return false;
    return $bytes;
}

function camada($s, $encoding)
{
    if ($encoding === 'WINDOWS-1252-PRESERVE-C1') {
        $bytes = cp1252_c1_encode($s);
        return $bytes !== false && valido_utf8($bytes) ? $bytes : false;
    }

    $bytes =
        @iconv(
            'UTF-8',
            $encoding,
            $s
        );


    if ($bytes === false) {
        return false;
    }


    if (
        !valido_utf8(
            $bytes
        )
    ) {
        return false;
    }


    if (@iconv($encoding, 'UTF-8', $bytes) !== $s) {
        return false;
    }

    return $bytes;
}


/*
 * ============================================================
 * SCORE DE MOJIBAKE
 *
 * Quanto menor, melhor.
 *
 * Somente score ZERO pode virar CORRIGIVEL automatico.
 * ============================================================
 */

function score_mojibake($s)
{
    $score = 0;


    /*
     * U+FFFD
     */
    $score +=
        substr_count(
            $s,
            "\xEF\xBF\xBD"
        ) * 10000;


    /*
     * Replacement reinterpretado como Latin1.
     */
    $score +=
        substr_count(
            $s,
            "\xC3\xAF\xC2\xBF\xC2\xBD"
        ) * 5000;


    /*
     * U+00AD - SOFT HYPHEN
     */
    $score +=
        substr_count(
            $s,
            "\xC2\xAD"
        ) * 1000;


    /*
     * U+200B - ZERO WIDTH SPACE
     */
    $score +=
        substr_count(
            $s,
            "\xE2\x80\x8B"
        ) * 1000;


    /*
     * U+200C
     */
    $score +=
        substr_count(
            $s,
            "\xE2\x80\x8C"
        ) * 1000;


    /*
     * U+2060
     */
    $score +=
        substr_count(
            $s,
            "\xE2\x81\xA0"
        ) * 1000;


    /*
     * BOM / ZERO WIDTH NO-BREAK SPACE
     */
    $score +=
        substr_count(
            $s,
            "\xEF\xBB\xBF"
        ) * 1000;


    /*
     * Padroes comuns de mojibake.
     */
    $patterns = array(

        // Bytes 80-9F exibidos como simbolos CP1252 apos um prefixo UTF8.
        // Evita encerrar em falso score zero, por exemplo C3 93 -> "Ã“".
        '/[\x{00C2}\x{00C3}][\x{20AC}\x{201A}\x{0192}\x{201E}\x{2026}\x{2020}\x{2021}\x{02C6}\x{2030}\x{0160}\x{2039}\x{0152}\x{017D}\x{2018}\x{2019}\x{201C}\x{201D}\x{2022}\x{2013}\x{2014}\x{02DC}\x{2122}\x{0161}\x{203A}\x{0153}\x{017E}\x{0178}]/u'
            => 40,

        '/\x{00C3}[\x{0080}-\x{00BF}]/u'
            => 40,

        '/\x{00C3}\x{0192}/u'
            => 80,

        '/\x{00C2}[\x{0080}-\x{00BF}]/u'
            => 35,

        '/\x{00E2}[\x{0080}-\x{009F}]/u'
            => 30,

        '/\x{00F0}[\x{0080}-\x{00BF}]/u'
            => 30,

        '/\x{00EF}[\x{0080}-\x{00BF}]/u'
            => 40,

        '/[\x{0080}-\x{009F}]/u'
            => 30
    );


    foreach (
        $patterns
        as $regex => $peso
    ) {

        $n =
            preg_match_all(
                $regex,
                $s,
                $m
            );


        if ($n !== false) {

            $score +=
                $n *
                $peso;
        }
    }


    return $score;
}


/*
 * ============================================================
 * DETECTA PERDA IRREVERSIVEL
 * ============================================================
 */

function possui_perda_irreversivel(
    $original,
    $max = 8
) {

    $fila = array(

        array(
            $original,
            0
        )
    );


    $vistos =
        array();


    while (
        !empty($fila)
    ) {

        $item =
            array_shift(
                $fila
            );

        $s =
            $item[0];

        $nivel =
            $item[1];


        $hash =
            md5($s);


        if (
            isset(
                $vistos[$hash]
            )
        ) {
            continue;
        }


        $vistos[$hash] =
            true;


        /*
         * U+FFFD real.
         */
        if (
            strpos(
                $s,
                "\xEF\xBF\xBD"
            ) !== false
        ) {
            return true;
        }


        /*
         * Replacement recodificado.
         */
        if (
            strpos(
                $s,
                "\xC3\xAF\xC2\xBF\xC2\xBD"
            ) !== false
        ) {
            return true;
        }


        if (
            $nivel >=
            $max
        ) {
            continue;
        }


        foreach (
            array(
                'ISO-8859-1',
                'WINDOWS-1252',
                'WINDOWS-1252-PRESERVE-C1'
            )
            as $enc
        ) {

            $novo =
                camada(
                    $s,
                    $enc
                );


            if (
                $novo !== false &&
                $novo !== $s
            ) {

                $fila[] = array(

                    $novo,

                    $nivel + 1
                );
            }
        }
    }


    return false;
}


/*
 * ============================================================
 * PROCURA MELHOR CORRECAO
 * ============================================================
 */

function melhor_correcao(
    $original,
    $max = 16
) {

    /*
     * ========================================================
     * BUSCA ADAPTATIVA
     * ========================================================
     *
     * - ate 16 camadas
     * - latin1 e cp1252
     * - mantem somente as melhores rotas de cada nivel
     * - evita explosao combinatoria
     * - nunca aceita U+FFFD
     * - somente score ZERO vira CORRIGIVEL
     */

    $scoreOriginal =
        score_mojibake(
            $original
        );


    if ($scoreOriginal === 0) {

        return array(

            'status'
                => 'OK',

            'texto'
                => $original,

            'camadas'
                => 0,

            'score_antes'
                => 0,

            'score_depois'
                => 0,

            'rota'
                => ''
        );
    }


    /*
     * Se existir perda real de caracteres,
     * preserva sem tentar adivinhar.
     */
    if (
        possui_perda_irreversivel(
            $original,
            $max
        )
    ) {

        return array(

            'status'
                => 'IRRECUPERAVEL',

            'texto'
                => $original,

            'camadas'
                => 0,

            'score_antes'
                => $scoreOriginal,

            'score_depois'
                => $scoreOriginal,

            'rota'
                => ''
        );
    }


    /*
     * Quantas melhores rotas mantemos por camada.
     *
     * 6 permite misturas latin1/cp1252 sem deixar
     * a quantidade de candidatos explodir.
     */
    $BEAM_WIDTH = 6;


    /*
     * Permite pequeno aumento temporario do score.
     *
     * Algumas recodificacoes profundas precisam passar
     * por uma camada intermediaria que nao melhora muito.
     */
    $TOLERANCIA = 120;


    /*
     * Se passarmos varias camadas sem qualquer melhora
     * global, podemos encerrar antes de chegar ao teto.
     */
    $MAX_SEM_MELHORA = 4;


    $melhor =
        $original;

    $melhorScore =
        $scoreOriginal;

    $melhorNivel =
        0;

    $melhorRota =
        '';


    /*
     * Nivel inicial.
     */
    $atuais = array(

        array(

            'texto'
                => $original,

            'score'
                => $scoreOriginal,

            'nivel'
                => 0,

            'rota'
                => ''
        )
    );


    $vistos =
        array(
            md5($original)
                => true
        );


    $semMelhora =
        0;


    for (
        $nivel = 1;
        $nivel <= $max;
        $nivel++
    ) {

        $scoreAntesDoNivel = $melhorScore;

        $proximos =
            array();


        foreach (
            $atuais
            as $estado
        ) {

            $textoAtual =
                $estado['texto'];

            $scoreAtual =
                $estado['score'];

            $rotaAtual =
                $estado['rota'];


            foreach (
                array(
                    'ISO-8859-1',
                    'WINDOWS-1252',
                'WINDOWS-1252-PRESERVE-C1'
                )
                as $enc
            ) {

                $novo =
                    camada(
                        $textoAtual,
                        $enc
                    );


                if (
                    $novo === false ||
                    $novo === $textoAtual
                ) {
                    continue;
                }


                /*
                 * Nunca continua por rota que gere replacement.
                 */
                if (
                    strpos(
                        $novo,
                        "\xEF\xBF\xBD"
                    ) !== false
                ) {
                    continue;
                }


                $hash =
                    md5($novo);


                if (
                    isset(
                        $vistos[$hash]
                    )
                ) {
                    continue;
                }


                $vistos[$hash] =
                    true;


                $novoScore =
                    score_mojibake(
                        $novo
                    );


                /*
                 * Evita caminhos claramente ruins.
                 *
                 * Mas permite pequena piora temporaria.
                 */
                if (
                    $novoScore >
                    (
                        $scoreAtual +
                        $TOLERANCIA
                    )
                ) {
                    continue;
                }


                $novaRota =
                    $rotaAtual;


                if (
                    $novaRota !==
                    ''
                ) {

                    $novaRota .=
                        ' > ';
                }


                $novaRota .=
                    $enc .
                    '->UTF8';


                $proximos[] = array(

                    'texto'
                        => $novo,

                    'score'
                        => $novoScore,

                    'nivel'
                        => $nivel,

                    'rota'
                        => $novaRota
                );


                /*
                 * Encontrou solucao perfeita.
                 *
                 * Pode retornar imediatamente.
                 */
                if (
                    $novoScore ===
                    0
                ) {

                    return array(

                        'status'
                            => 'CORRIGIVEL',

                        'texto'
                            => $novo,

                        'camadas'
                            => $nivel,

                        'score_antes'
                            => $scoreOriginal,

                        'score_depois'
                            => 0,

                        'rota'
                            => $novaRota
                    );
                }


                /*
                 * Atualiza melhor resultado parcial.
                 */
                if (
                    $novoScore <
                    $melhorScore
                ) {

                    $melhor =
                        $novo;

                    $melhorScore =
                        $novoScore;

                    $melhorNivel =
                        $nivel;

                    $melhorRota =
                        $novaRota;
                }
            }
        }


        /*
         * Nenhuma rota sobreviveu.
         */
        if (
            empty(
                $proximos
            )
        ) {
            break;
        }


        /*
         * Ordena pelo menor score.
         */
        usort(
            $proximos,
            function($a, $b) {

                if (
                    $a['score'] ==
                    $b['score']
                ) {

                    return
                        $a['nivel'] -
                        $b['nivel'];
                }


                return
                    $a['score'] -
                    $b['score'];
            }
        );


        /*
         * Mantem somente as melhores rotas.
         */
        $atuais =
            array_slice(
                $proximos,
                0,
                $BEAM_WIDTH
            );


        /*
         * Controle de progresso.
         */
        $melhorNivelAtual =
            $atuais[0]['score'];


        if (
            $melhorNivelAtual <
            $scoreAntesDoNivel
        ) {

            $semMelhora =
                0;

        } else {

            $semMelhora++;
        }


        /*
         * Nao abandona cedo demais:
         * somente depois da oitava camada.
         */
        if (
            $nivel >= 8 &&
            $semMelhora >=
            $MAX_SEM_MELHORA
        ) {

            break;
        }
    }


    /*
     * Chegou a uma versao melhor, mas nao perfeita.
     */
    if (
        $melhorScore <
        $scoreOriginal
    ) {

        return array(

            'status'
                => 'PARCIAL',

            'texto'
                => $melhor,

            'camadas'
                => $melhorNivel,

            'score_antes'
                => $scoreOriginal,

            'score_depois'
                => $melhorScore,

            'rota'
                => $melhorRota
        );
    }


    /*
     * Nao encontrou caminho confiavel.
     */
    return array(

        'status'
            => 'SUSPEITO',

        'texto'
            => $original,

        'camadas'
            => 0,

        'score_antes'
            => $scoreOriginal,

        'score_depois'
            => $scoreOriginal,

        'rota'
            => ''
    );
}

/*
 * ============================================================
 * CONEXAO MYSQL/MARIADB
 * ============================================================
 */

mysqli_report(
    MYSQLI_REPORT_OFF
);


$db =
    null;

$conexaoUsada =
    '';

$dumpTipo =
    '';

$dumpSocket =
    '';


/*
 * Primeiro TCP.
 */
$tmp =
    mysqli_init();


if ($tmp) {

    $ok =
        @$tmp->real_connect(
            '127.0.0.1',
            $DB_USER,
            $DB_PASS,
            $DB_NAME,
            3306
        );


    if ($ok) {

        $db =
            $tmp;

        $conexaoUsada =
            'TCP 127.0.0.1:3306';

        $dumpTipo =
            'TCP';

    } else {

        @$tmp->close();
    }
}


/*
 * Depois sockets.
 */
if (!$db) {

    $sockets = array(

        '/run/mysqld/mysqld.sock',

        '/var/run/mysqld/mysqld.sock',

        '/var/lib/mysql/mysql.sock',

        '/var/lib/mysqld/mysqld.sock',

        '/tmp/mysql.sock'
    );


    foreach (
        $sockets
        as $socket
    ) {

        if (
            !file_exists(
                $socket
            )
        ) {
            continue;
        }


        $tmp =
            mysqli_init();


        if (!$tmp) {
            continue;
        }


        $ok =
            @$tmp->real_connect(
                'localhost',
                $DB_USER,
                $DB_PASS,
                $DB_NAME,
                0,
                $socket
            );


        if ($ok) {

            $db =
                $tmp;

            $conexaoUsada =
                'SOCKET ' .
                $socket;

            $dumpTipo =
                'SOCKET';

            $dumpSocket =
                $socket;

            break;
        }


        @$tmp->close();
    }
}


if (!$db) {

    fwrite(
        STDERR,
        'ERRO: nao foi possivel conectar ao MySQL/MariaDB.' .
        PHP_EOL
    );

    exit(1);
}


/*
 * A aplicacao trabalha internamente em UTF-8.
 */
if (
    !$db->set_charset(
        'utf8mb4'
    )
) {

    fwrite(
        STDERR,
        'ERRO ao configurar utf8mb4 na sessao MySQL.' .
        PHP_EOL
    );

    exit(1);
}


echo
    'MYSQL: conectado via ' .
    $conexaoUsada .
    PHP_EOL;


/*
 * ============================================================
 * DESCOBRE CHAVE DA TABELA
 * ============================================================
 */

$cacheChaves =
    array();


function chave_tabela($tabela)
{
    global $db, $DB_NAME, $cacheChaves;
    if (array_key_exists($tabela, $cacheChaves)) {
        return $cacheChaves[$tabela];
    }
    $t = $db->real_escape_string($tabela);
    $schema = $db->real_escape_string($DB_NAME);
    $q = $db->query("SELECT s.INDEX_NAME, s.COLUMN_NAME, s.SUB_PART, c.IS_NULLABLE
        FROM information_schema.STATISTICS s
        LEFT JOIN information_schema.COLUMNS c
          ON c.TABLE_SCHEMA=s.TABLE_SCHEMA AND c.TABLE_NAME=s.TABLE_NAME
         AND c.COLUMN_NAME=s.COLUMN_NAME
        WHERE s.TABLE_SCHEMA='{$schema}' AND s.TABLE_NAME='{$t}' AND s.NON_UNIQUE=0
        ORDER BY (s.INDEX_NAME='PRIMARY') DESC, s.INDEX_NAME, s.SEQ_IN_INDEX");
    if (!$q) {
        falhar('ERRO ao consultar chaves: ' . $db->error);
    }
    $indices = array();
    $invalidos = array();
    while ($r = $q->fetch_assoc()) {
        $indices[$r['INDEX_NAME']][] = $r['COLUMN_NAME'];
        if ($r['COLUMN_NAME'] === null || $r['IS_NULLABLE'] !== 'NO' || $r['SUB_PART'] !== null) {
            $invalidos[$r['INDEX_NAME']] = true;
        }
    }
    foreach ($indices as $nome => $colunas) {
        if (!isset($invalidos[$nome])) {
            return $cacheChaves[$tabela] = $colunas;
        }
    }
    return $cacheChaves[$tabela] = array();
}

/*
 * ============================================================
 * CABECALHO
 * ============================================================
 */

logmsg(
    '============================================================'
);

logmsg(
    'MK-AUTH - CORRETOR UNIVERSAL DE ACENTUACAO'
);

logmsg(
    '============================================================'
);

logmsg(
    'Versao.............: ' .
    $VERSAO
);

logmsg(
    'PHP................: ' .
    PHP_VERSION
);

logmsg(
    'Banco..............: ' .
    $DB_NAME
);

logmsg(
    'Modo...............: ' .
    (
        $APPLY
        ? 'APLICAR'
        : 'SOMENTE ANALISE'
    )
);

logmsg(
    'Historico..........: ' .
    (
        $INCLUDE_HISTORY
        ? 'INCLUIDO'
        : 'IGNORADO'
    )
);

logmsg(
    'Maximo de camadas..: ' .
    $MAX_CAMADAS
);

logmsg('');


/*
 * ============================================================
 * DESCOBRE TODAS AS COLUNAS DE TEXTO
 * ============================================================
 */

$sql = "
SELECT
    c.TABLE_NAME,
    c.COLUMN_NAME,
    c.CHARACTER_SET_NAME,
    c.COLLATION_NAME

FROM
    information_schema.COLUMNS c

JOIN
    information_schema.TABLES t

      ON t.TABLE_SCHEMA=c.TABLE_SCHEMA
     AND t.TABLE_NAME=c.TABLE_NAME

WHERE
    c.TABLE_SCHEMA='{$DB_NAME}'

    AND t.TABLE_TYPE='BASE TABLE'

    AND c.DATA_TYPE IN (
        'char',
        'varchar',
        'tinytext',
        'text',
        'mediumtext',
        'longtext'
    )

ORDER BY
    c.TABLE_NAME,
    c.ORDINAL_POSITION
";


$res =
    $db->query(
        $sql
    );


if (!$res) {

    falhar(
        'ERRO consultando estrutura: ' .
        $db->error .
        PHP_EOL
    );
}


/*
 * ============================================================
 * VARREDURA
 * ============================================================
 */

$alteracoes =
    array();

$totalExaminados =
    0;

$totalCorrigiveis =
    0;

$totalParciais =
    0;

$totalIrrecuperaveis =
    0;

$totalSuspeitos =
    0;

$totalSemChave =
    0;
$totalErrosLeitura = 0;


while (
    $col =
    $res->fetch_assoc()
) {

    $tabela =
        $col['TABLE_NAME'];

    $campo =
        $col['COLUMN_NAME'];


    /*
     * Historicos ficam fora por padrao.
     */
    if (
        !$INCLUDE_HISTORY &&
        in_array(
            $tabela,
            $IGNORAR,
            true
        )
    ) {
        continue;
    }


    $chaves =
        chave_tabela(
            $tabela
        );


    if (
        empty(
            $chaves
        )
    ) {

        $totalSemChave++;


        logmsg(
            '[SEM CHAVE] ' .
            $tabela .
            '.' .
            $campo
        );


        continue;
    }


    $selectCampos =
        array();


    foreach (
        $chaves
        as $c
    ) {

        $selectCampos[] =
            ident($c);
    }


    $selectCampos[] =
        ident($campo);


    /*
     * IMPORTANTE:
     *
     * Guarda os bytes EXATOS existentes no banco.
     *
     * HEX() nao sofre a conversao latin1/utf8mb4 da conexao.
     *
     * Isso e usado posteriormente como trava do UPDATE.
     */
    $selectCampos[] =
        'HEX(' .
        ident($campo) .
        ') AS `__mkauth_original_hex`';


    $qsql =
        'SELECT ' .
        implode(
            ',',
            $selectCampos
        ) .
        ' FROM ' .
        ident($tabela) .
        ' WHERE ' .
        ident($campo) .
        ' IS NOT NULL AND ' .
        ident($campo) .
        " <> ''";


    $qr =
        $db->query(
            $qsql
        );


    if (!$qr) {
        $totalErrosLeitura++;

        logmsg(
            '[ERRO SELECT] ' .
            $tabela .
            '.' .
            $campo .
            ': ' .
            $db->error
        );


        continue;
    }


    while (
        $row =
        $qr->fetch_assoc()
    ) {

        $original =
            $row[$campo];


        /*
         * A sessao MySQL deve entregar UTF-8 valido.
         */
        if (
            !valido_utf8(
                $original
            )
        ) {
            continue;
        }


        $score =
            score_mojibake(
                $original
            );


        /*
         * Nao suspeito.
         */
        if (
            $score ===
            0
        ) {
            continue;
        }


        $totalExaminados++;


        $analise =
            melhor_correcao(
                $original,
                $MAX_CAMADAS
            );


        $identificacao =
            array();


        foreach (
            $chaves
            as $c
        ) {

            $identificacao[] =
                $c .
                '=' .
                (
                    isset(
                        $row[$c]
                    )
                    ? $row[$c]
                    : 'NULL'
                );
        }


        $idtxt =
            implode(
                ',',
                $identificacao
            );


        switch (
            $analise['status']
        ) {

            case 'CORRIGIVEL':

                $totalCorrigiveis++;


                logmsg(
                    '[CORRIGIVEL] ' .
                    $tabela .
                    '.' .
                    $campo .
                    ' | ' .
                    $idtxt
                );


                logmsg(
                    '  ANTES : ' .
                    resumo(
                        $original
                    )
                );


                logmsg(
                    '  DEPOIS: ' .
                    resumo(
                        $analise['texto']
                    )
                );


                logmsg(
                    '  CAMADAS: ' .
                    $analise['camadas']
                );


                logmsg(
                    '  ROTA...: ' .
                    $analise['rota']
                );


                $chaveAuditada = array();
                foreach ($chaves as $c) {
                    $chaveAuditada[$c] = $row[$c];
                }
                auditar(array(
                    'evento' => 'CANDIDATO', 'versao' => $VERSAO,
                    'tabela' => $tabela, 'campo' => $campo,
                    'chave' => $chaveAuditada,
                    'original_hex' => $row['__mkauth_original_hex'],
                    'antes' => $original, 'depois' => $analise['texto'],
                    'camadas' => $analise['camadas'], 'rota' => $analise['rota']
                ));

                $alteracoes[] =
                    array(

                        'tabela'
                            => $tabela,

                        'campo'
                            => $campo,

                        'chaves'
                            => $chaves,

                        'row'
                            => $row,

                        'original'
                            => $original,

                        'original_hex'
                            => $row[
                                '__mkauth_original_hex'
                            ],

                        'novo'
                            => $analise['texto']
                    );


                break;


            case 'IRRECUPERAVEL':

                $totalIrrecuperaveis++;


                logmsg(
                    '[IRRECUPERAVEL] ' .
                    $tabela .
                    '.' .
                    $campo .
                    ' | ' .
                    $idtxt
                );


                logmsg(
                    '  TEXTO: ' .
                    resumo(
                        $original
                    )
                );


                file_put_contents(

                    $IRRECUPERAVEIS,

                    $tabela .
                    '.' .
                    $campo .
                    ' | ' .
                    $idtxt .
                    PHP_EOL .

                    resumo(
                        $original,
                        1500
                    ) .
                    PHP_EOL .

                    str_repeat(
                        '-',
                        80
                    ) .
                    PHP_EOL,

                    FILE_APPEND
                );


                break;


            case 'PARCIAL':

                $totalParciais++;


                logmsg(
                    '[PARCIAL] ' .
                    $tabela .
                    '.' .
                    $campo .
                    ' | ' .
                    $idtxt
                );


                logmsg(
                    '  ANTES : ' .
                    resumo(
                        $original
                    )
                );


                logmsg(
                    '  MELHOR: ' .
                    resumo(
                        $analise['texto']
                    )
                );


                logmsg(
                    '  SCORE: ' .
                    $analise['score_antes'] .
                    ' -> ' .
                    $analise['score_depois']
                );


                break;


            default:

                $totalSuspeitos++;


                logmsg(
                    '[SUSPEITO] ' .
                    $tabela .
                    '.' .
                    $campo .
                    ' | ' .
                    $idtxt
                );


                logmsg(
                    '  TEXTO: ' .
                    resumo(
                        $original
                    )
                );


                break;
        }
    }
}


/*
 * ============================================================
 * RESUMO DA ANALISE
 * ============================================================
 */

logmsg('');

logmsg(
    '============================================================'
);

logmsg(
    'RESUMO DA ANALISE'
);

logmsg(
    '============================================================'
);

logmsg(
    'Campos suspeitos examinados....: ' .
    $totalExaminados
);

logmsg(
    'Automaticamente corrigiveis....: ' .
    $totalCorrigiveis
);

logmsg(
    'Parciais preservados...........: ' .
    $totalParciais
);

logmsg(
    'Perda irreversivel.............: ' .
    $totalIrrecuperaveis
);

logmsg(
    'Outros suspeitos...............: ' .
    $totalSuspeitos
);

logmsg(
    'Colunas sem chave..............: ' .
    $totalSemChave
);


/*
 * ============================================================
 * MODO SOMENTE ANALISE
 * ============================================================
 */

if ($totalCorrigiveis > 0) {
    logmsg('Auditoria completa dos candidatos: ' . $AUDITORIA);
}
if ($totalErrosLeitura > 0) {
    logmsg('ERRO: analise incompleta; nenhum UPDATE sera executado.');
    exit(1);
}

if (!$APPLY) {

    logmsg('');


    logmsg(
        'NENHUM UPDATE FOI EXECUTADO.'
    );


    logmsg(
        'Relatorio: ' .
        $LOG
    );


    if (
        $totalIrrecuperaveis >
        0
    ) {

        logmsg(
            'Irrecuperaveis: ' .
            $IRRECUPERAVEIS
        );
    }


    exit(0);
}


/*
 * ============================================================
 * NADA PARA CORRIGIR
 * ============================================================
 */

if (
    empty(
        $alteracoes
    )
) {

    logmsg('');


    logmsg(
        'Nada para corrigir automaticamente.'
    );


    exit(0);
}


/*
 * ============================================================
 * BACKUP DAS TABELAS QUE SERAO ALTERADAS
 * ============================================================
 */

$tabelasBackup =
    array();


foreach (
    $alteracoes
    as $a
) {

    $tabelasBackup[
        $a['tabela']
    ] = true;
}


$tabelasBackup =
    array_keys(
        $tabelasBackup
    );


$backup =
    $OUTPUT_DIR . '/mkradius_antes_acento_' .
    $TS .
    '.sql';


/*
 * MYSQL_PWD evita senha aparecendo na linha de processo.
 */
$cmd =
    'MYSQL_PWD=' .
    escapeshellarg(
        $DB_PASS
    ) .
    ' mysqldump ';


if (
    $dumpTipo ===
    'TCP'
) {

    $cmd .=
        '-h 127.0.0.1 ' .
        '-P 3306 ';

} else {

    $cmd .=
        '--socket=' .
        escapeshellarg(
            $dumpSocket
        ) .
        ' ';
}


$cmd .=
    '-u ' .
    escapeshellarg(
        $DB_USER
    ) .
    ' ' .
    escapeshellarg(
        $DB_NAME
    ) .
    ' ';


foreach (
    $tabelasBackup
    as $t
) {

    $cmd .=
        escapeshellarg(
            $t
        ) .
        ' ';
}


$cmd .=
    '> ' .
    escapeshellarg(
        $backup
    );


logmsg('');

logmsg(
    'Criando backup antes dos UPDATEs...'
);


system(
    $cmd,
    $retBackup
);


if (
    $retBackup !==
    0
) {

    falhar(
        'ERRO: backup falhou. Nenhum UPDATE foi executado.' .
        PHP_EOL
    );
}


/*
 * Confere que o arquivo realmente existe.
 */
if (
    !file_exists(
        $backup
    ) ||
    filesize(
        $backup
    ) <= 0
) {

    falhar(
        'ERRO: backup vazio. Nenhum UPDATE foi executado.' .
        PHP_EOL
    );
}


logmsg(
    'BACKUP: ' .
    $backup
);


/*
 * ============================================================
 * APLICACAO
 * ============================================================
 */

if (!$db->query("SET SESSION sql_mode = CONCAT_WS(',', NULLIF(@@SESSION.sql_mode, ''), 'STRICT_ALL_TABLES')")) {
    logmsg('ERRO: nao foi possivel ativar escrita estrita; nenhum UPDATE executado.');
    exit(1);
}

$totalAplicados =
    0;

$totalNaoAlterados =
    0;

$totalErros =
    0;


foreach (
    $alteracoes
    as $a
) {

    $tabela =
        $a['tabela'];

    $campo =
        $a['campo'];


    $novo =
        $db->real_escape_string(
            $a['novo']
        );


    $where =
        array();


    /*
     * Identifica o registro pelas chaves.
     */
    foreach (
        $a['chaves']
        as $c
    ) {

        $valor =
            $a['row'][$c];


        if (
            $valor ===
            null
        ) {

            $where[] =
                ident($c) .
                ' IS NULL';

        } else {

            $where[] =
                ident($c) .
                "='" .
                $db->real_escape_string(
                    $valor
                ) .
                "'";
        }
    }


    /*
     * ========================================================
     * TRAVA UNIVERSAL POR HEX
     * ========================================================
     *
     * O campo somente sera alterado se os bytes atualmente
     * armazenados ainda forem EXATAMENTE os bytes analisados.
     *
     * Isso evita o problema:
     *
     *   coluna latin1
     *      x
     *   conexao PHP utf8mb4
     *
     * e tambem protege contra alteracao concorrente.
     */

    $originalHex =
        strtoupper(
            $a['original_hex']
        );


    $where[] =
        'HEX(' .
        ident($campo) .
        ")='" .
        $db->real_escape_string(
            $originalHex
        ) .
        "'";


    $usql =
        'UPDATE ' .
        ident($tabela) .
        ' SET ' .
        ident($campo) .
        "='" .
        $novo .
        "' WHERE " .
        implode(
            ' AND ',
            $where
        ) .
        ' LIMIT 1';


    if (
        $db->query(
            $usql
        )
    ) {

        if (
            $db->affected_rows ===
            1
        ) {

            $totalAplicados++;
            auditar(array(
                'evento' => 'CORRIGIDO', 'tabela' => $tabela,
                'campo' => $campo,
                'chave' => array_intersect_key($a['row'], array_flip($a['chaves'])),
                'original_hex' => $originalHex, 'depois' => $a['novo']
            ));



            logmsg(
                '[CORRIGIDO] ' .
                $tabela .
                '.' .
                $campo
            );

        } else {

            $totalNaoAlterados++;


            logmsg(
                '[NAO ALTERADO] ' .
                $tabela .
                '.' .
                $campo
            );
        }

    } else {

        $totalErros++;


        logmsg(
            '[ERRO UPDATE] ' .
            $tabela .
            '.' .
            $campo .
            ': ' .
            $db->error
        );
    }
}


/*
 * ============================================================
 * RESULTADO FINAL
 * ============================================================
 */

logmsg('');

logmsg(
    '============================================================'
);

logmsg(
    'RESULTADO FINAL'
);

logmsg(
    '============================================================'
);

logmsg(
    'Campos corrigidos...............: ' .
    $totalAplicados
);

logmsg(
    'Nao alterados...................: ' .
    $totalNaoAlterados
);

logmsg(
    'Erros...........................: ' .
    $totalErros
);

logmsg(
    'Parciais preservados............: ' .
    $totalParciais
);

logmsg(
    'Perdas irreversiveis preservadas: ' .
    $totalIrrecuperaveis
);

logmsg(
    'Outros suspeitos preservados....: ' .
    $totalSuspeitos
);

logmsg(
    'BACKUP: ' .
    $backup
);

logmsg(
    'LOG...: ' .
    $LOG
);


if (
    $totalIrrecuperaveis >
    0
) {

    logmsg(
        'IRRECUPERAVEIS: ' .
        $IRRECUPERAVEIS
    );
}


logmsg('');

logmsg(
    'FIM.'
);
exit($totalErros > 0 ? 1 : 0);
MKAUTH_PHP
cat > "$STAGE/menu.sh" <<'MKAUTH_MENU'
#!/bin/bash

CORRETOR="/root/mkauth_corrige_acentos.php"


# ============================================================
# DETECCAO DINAMICA DE PHP
#
# ESTA FUNCAO RODA NOVAMENTE TODA VEZ QUE O MENU E ABERTO.
# ============================================================

detectar_php()
{
    CANDIDATOS=""

    # Primeiro o PHP padrao atual.
    if command -v php >/dev/null 2>&1; then
        CANDIDATOS="$(command -v php)"
    fi


    # Depois outras versoes instaladas.
    for CAND in \
        php8.5 php8.4 php8.3 php8.2 php8.1 php8.0 \
        php7.4 php7.3 php7.2 php7.1 php7.0
    do

        if command -v "$CAND" >/dev/null 2>&1; then

            BIN="$(command -v "$CAND")"

            JA_EXISTE=0


            for EXISTENTE in $CANDIDATOS
            do

                if [ "$EXISTENTE" = "$BIN" ]; then

                    JA_EXISTE=1

                    break
                fi
            done


            if [ "$JA_EXISTE" -eq 0 ]; then

                CANDIDATOS="$CANDIDATOS $BIN"
            fi
        fi
    done


    # Primeiro PHP funcional ganha.
    for BIN in $CANDIDATOS
    do

        if "$BIN" -r '
            if (PHP_VERSION_ID < 70000) {
                exit(1);
            }

            if (!extension_loaded("mysqli")) {
                exit(1);
            }

            if (!extension_loaded("iconv")) {
                exit(1);
            }

            exit(0);
        ' >/dev/null 2>&1
        then

            echo "$BIN"

            return 0
        fi
    done


    return 1
}


PHP_BIN="$(detectar_php)"


if [ -z "$PHP_BIN" ]; then

    echo
    echo "ERRO:"
    echo "Nenhum PHP 7/8 com mysqli + iconv foi encontrado."
    echo

    exit 1
fi


if [ ! -f "$CORRETOR" ]; then

    echo
    echo "ERRO:"
    echo "Corretor nao encontrado:"
    echo "$CORRETOR"
    echo

    exit 1
fi


# ============================================================
# FUNCOES DO MENU
# ============================================================

pausa()
{
    echo
    echo "============================================================"
    echo " Pressione ENTER para continuar"
    echo "============================================================"

    read -r || return 0
}


mostrar_php()
{
    echo "PHP selecionado dinamicamente:"
    echo "$PHP_BIN"

    "$PHP_BIN" -v | head -1
}


executar()
{
    clear

    echo "============================================================"
    echo " MK-AUTH - CORRETOR UNIVERSAL DE ACENTUACAO"
    echo "============================================================"
    echo

    mostrar_php

    echo

    "$PHP_BIN" "$CORRETOR" "$@"

    pausa
}



while true
do

    clear

    echo "============================================================"
    echo "        MK-AUTH - CORRETOR DE ACENTUACAO"
    echo "============================================================"
    echo

    mostrar_php

    echo
    echo "------------------------------------------------------------"
    echo
    echo "  1 - Somente analisar"
    echo
    echo "  2 - Corrigir automaticamente"
    echo
    echo "  3 - Analisar incluindo historicos"
    echo
    echo "  4 - Corrigir incluindo historicos"
    echo
    echo "  5 - Ver ultimos backups"
    echo
    echo "  6 - Ver ultimo relatorio"
    echo
    echo "  7 - Validar corretor"
    echo
    echo "  8 - Mostrar ambiente"
    echo
    echo "  9 - Mostrar casos preservados"
    echo
    echo "  0 - Sair"
    echo
    echo "------------------------------------------------------------"
    echo

    read -rp "Escolha uma opcao: " OPCAO || exit 0


    case "$OPCAO" in

        1)

            executar

            ;;


        2)

            clear

            echo "============================================================"
            echo " CORRECAO AUTOMATICA"
            echo "============================================================"
            echo
            echo "Sera criado um backup antes dos UPDATEs."
            echo
            echo "O corretor altera SOMENTE casos classificados"
            echo "como CORRIGIVEL."
            echo
            echo "PARCIAL, SUSPEITO e IRRECUPERAVEL"
            echo "serao preservados."
            echo
            echo "Digite exatamente:"
            echo
            echo "Revise antes TODOS os CORRIGIVEL no relatorio e no arquivo JSONL."
            echo "CORRIGIR"
            echo

            read -rp "> " CONFIRMA


            if [ "$CONFIRMA" = "CORRIGIR" ]; then

                executar --apply

            else

                echo
                echo "Operacao cancelada."

                sleep 2
            fi

            ;;


        3)

            executar --include-history

            ;;


        4)

            clear

            echo "============================================================"
            echo " CORRECAO COM HISTORICOS"
            echo "============================================================"
            echo
            echo "ATENCAO:"
            echo
            echo "Esta opcao pode analisar milhares ou milhoes"
            echo "de mensagens e registros antigos."
            echo
            echo "Digite exatamente:"
            echo
            echo "Revise antes TODOS os CORRIGIVEL no relatorio e no arquivo JSONL."
            echo "HISTORICO"
            echo

            read -rp "> " CONFIRMA


            if [ "$CONFIRMA" = "HISTORICO" ]; then

                executar --apply --include-history

            else

                echo
                echo "Operacao cancelada."

                sleep 2
            fi

            ;;


        5)

            clear

            echo "============================================================"
            echo " ULTIMOS BACKUPS"
            echo "============================================================"
            echo


            if ls /root/mkradius_antes_acento_*.sql \
                >/dev/null 2>&1
            then

                ls -lht \
                    /root/mkradius_antes_acento_*.sql \
                    | head -20

            else

                echo "Nenhum backup encontrado."
            fi


            pausa

            ;;


        6)

            clear


            LOG="$(
                ls -1t \
                    /root/mkauth_acento_*.log \
                    2>/dev/null \
                    | head -1
            )"


            echo "============================================================"
            echo " ULTIMO RELATORIO"
            echo "============================================================"
            echo


            if [ -n "$LOG" ]; then

                echo "Arquivo:"
                echo "$LOG"
                echo

                tail -120 "$LOG"

            else

                echo "Nenhum relatorio encontrado."
            fi


            pausa

            ;;


        7)

            clear

            echo "============================================================"
            echo " VALIDACAO DO CORRETOR"
            echo "============================================================"
            echo

            mostrar_php

            echo

            "$PHP_BIN" -l "$CORRETOR"

            echo

            if grep -q '__mkauth_original_hex' "$CORRETOR" && \
               grep -q "'original_hex'" "$CORRETOR"
            then

                echo "Protecao HEX: OK"

            else

                echo "Protecao HEX: FALHANDO"
            fi


            pausa

            ;;


        8)

            clear

            echo "============================================================"
            echo " AMBIENTE ATUAL"
            echo "============================================================"
            echo

            mostrar_php

            echo
            echo "PHP ID:"

            "$PHP_BIN" -r \
                'echo PHP_VERSION_ID . PHP_EOL;'

            echo
            echo "mysqli:"

            "$PHP_BIN" -r '
                echo
                    extension_loaded("mysqli")
                    ? "OK\n"
                    : "FALTA\n";
            '

            echo
            echo "iconv:"

            "$PHP_BIN" -r '
                echo
                    extension_loaded("iconv")
                    ? "OK\n"
                    : "FALTA\n";
            '

            echo
            echo "MySQL/MariaDB:"


            mysql \
                -uroot \
                -pvertrigo \
                -Nse \
                "SELECT VERSION();" \
                2>/dev/null


            echo
            echo "Charsets:"


            mysql \
                -uroot \
                -pvertrigo \
                -Nse \
                "
                SHOW VARIABLES LIKE 'character_set_database';
                SHOW VARIABLES LIKE 'collation_database';
                SHOW VARIABLES LIKE 'character_set_server';
                SHOW VARIABLES LIKE 'collation_server';
                " \
                2>/dev/null


            echo
            echo "Socket:"


            mysql \
                -uroot \
                -pvertrigo \
                -Nse \
                "SHOW VARIABLES LIKE 'socket';" \
                2>/dev/null


            pausa

            ;;


        9)

            clear

            LOG="$(
                ls -1t \
                    /root/mkauth_acento_*.log \
                    2>/dev/null \
                    | head -1
            )"


            echo "============================================================"
            echo " CASOS PRESERVADOS NO ULTIMO RELATORIO"
            echo "============================================================"
            echo


            if [ -z "$LOG" ]; then

                echo "Nenhum relatorio encontrado."

            else

                echo "PARCIAIS:"
                echo

                grep -A4 \
                    '\[PARCIAL\]' \
                    "$LOG" \
                    2>/dev/null \
                    | head -100


                echo
                echo "------------------------------------------------------------"
                echo
                echo "SUSPEITOS:"
                echo

                grep -A2 \
                    '\[SUSPEITO\]' \
                    "$LOG" \
                    2>/dev/null \
                    | head -100


                echo
                echo "------------------------------------------------------------"
                echo
                echo "IRRECUPERAVEIS:"
                echo

                grep -A2 \
                    '\[IRRECUPERAVEL\]' \
                    "$LOG" \
                    2>/dev/null \
                    | head -100
            fi


            pausa

            ;;


        0)

            clear

            exit 0

            ;;


        *)

            echo
            echo "Opcao invalida."

            sleep 2

            ;;

    esac

done
MKAUTH_MENU

"$PHP_BIN" -l "$STAGE/corretor.php"
bash -n "$STAGE/menu.sh"
grep -q '__mkauth_original_hex' "$STAGE/corretor.php"
grep -q 'UNIVERSAL-HEX-R17' "$STAGE/corretor.php"
TS="$(date +%Y%m%d-%H%M%S)-$$"
# Ambas as copias sao validadas ANTES de substituir arquivos instalados.
# Falha em qualquer backup interrompe a instalacao.
for ALVO in "$CORRETOR" "$MENU"; do
    if [ -e "$ALVO" ]; then
        cp -a -- "$ALVO" "${ALVO}.bkp-instalador-${TS}"
        echo "Backup: ${ALVO}.bkp-instalador-${TS}"
    fi
done
install -m 700 "$STAGE/corretor.php" "$CORRETOR"
install -m 755 "$STAGE/menu.sh" "$MENU"
echo "Instalado: $VERSAO (R17)"
echo "PHP: $PHP_BIN"
echo "Use: mkauth-acento -> 1 (somente analisar)."
echo "Revise o resumo e TODOS os CORRIGIVEL antes de qualquer --apply."
echo "Instalacao concluida sem executar o corretor."
