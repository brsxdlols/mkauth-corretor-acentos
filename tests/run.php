<?php
// Testes sinteticos: carregam SOMENTE funcoes; sem conexao com banco.
$arquivo = isset($argv[1]) ? $argv[1] : __DIR__ . '/../instalar_mkauth_acento.sh';
$conteudo = file_get_contents($arquivo);
if (strpos($conteudo, "<<'MKAUTH_PHP'\n") !== false) {
    $conteudo = explode("<<'MKAUTH_PHP'\n", $conteudo, 2)[1];
    $conteudo = explode("\nMKAUTH_PHP\n", $conteudo, 2)[0];
}
$inicio = strpos($conteudo, 'function logmsg(');
$fim = strpos($conteudo, 'mysqli_report(');
if ($inicio === false || $fim === false || $fim <= $inicio) {
    fwrite(STDERR, "ERRO: bloco de funcoes nao encontrado.\n");
    exit(1);
}
eval(substr($conteudo, $inicio, $fim - $inicio));
$total = 0;
$falhas = 0;
function verificar($condicao, $nome) {
    global $total, $falhas;
    $total++;
    if (!$condicao) {
        $falhas++;
        echo 'FALHOU: ' . $nome . PHP_EOL;
    }
}
function corromper($texto, $encoding, $camadas) {
    for ($i = 0; $i < $camadas; $i++) {
        $texto = iconv($encoding, 'UTF-8', $texto);
    }
    return $texto;
}
$corretos = array(
    '', 'Texto ASCII 123', 'João', 'CONCEIÇÃO', 'São Luís',
    '1ª Travessa', '3º Andar', 'ÁÉÍÓÚ áéíóú Àà Ââ Êê Ôô Ãã Õõ Çç',
    '€ 25 — teste “aspas”', '日本語', '😀', "Cafe\xCC\x81"
);
foreach ($corretos as $i => $texto) {
    $r = melhor_correcao($texto, 16);
    verificar($r['status'] === 'OK' && $r['texto'] === $texto, 'preservar correto ' . $i);
}
foreach (array('João', 'ação', '1ª Avenida', '3º Andar', 'Çãé') as $i => $texto) {
    foreach (array(1, 2, 3, 8, 9, 12, 16) as $n) {
        $entrada = corromper($texto, 'ISO-8859-1', $n);
        $r = melhor_correcao($entrada, 16);
        verificar($r['status'] === 'CORRIGIVEL' && $r['texto'] === $texto && $r['camadas'] === $n,
            'latin1 texto ' . $i . ' camadas ' . $n);
        if ($r['status'] === 'CORRIGIVEL') {
            verificar(melhor_correcao($r['texto'], 16)['status'] === 'OK', 'idempotencia ' . $i . '/' . $n);
        }
    }
}
foreach (array('João', 'ação', 'Çãé') as $i => $texto) {
    foreach (array(1, 2, 3, 4) as $n) {
        $entrada = corromper($texto, 'WINDOWS-1252', $n);
        $r = melhor_correcao($entrada, 16);
        verificar($r['status'] === 'CORRIGIVEL' && $r['texto'] === $texto, 'cp1252 ' . $i . '/' . $n);
    }
}
foreach (array("Teste \xEF\xBF\xBD", corromper("Teste \xEF\xBF\xBD", 'ISO-8859-1', 3)) as $i => $texto) {
    $r = melhor_correcao($texto, 16);
    verificar($r['status'] === 'IRRECUPERAVEL' && $r['texto'] === $texto, 'perda preservada ' . $i);
}
$preservados = array(
    '3Âª Travessa João Exemplo',
    '1Âª Travessa João Exemplo',
    'Rua Exemplo DÃƒÆ’Ã‚',
    'Pessoa ÃƒÆ’Ã‚Âurea Exemplo',
    'CAMAÃƒÆ’ââ‚¬Â¡ARI',
    'Referencia Exemplo BirÃƒÆ’Ã¢â‚¬Â',
    'PESSOA EXEMPLO CONCEIÃƒÆ’Ã¢â‚¬Â¡Ã£O',
    "Texto\xC2\xAD", "Texto\xE2\x80\x8B"
);
foreach ($preservados as $i => $texto) {
    $r = melhor_correcao($texto, 16);
    verificar(in_array($r['status'], array('PARCIAL', 'SUSPEITO', 'IRRECUPERAVEL'), true), 'preservar misto/truncado ' . $i);
}
verificar(camada('João', 'ISO-8859-1') === false, 'nao reinterpretar UTF8 correto');
$r = melhor_correcao(corromper('João', 'ISO-8859-1', 9), 8);
verificar($r['status'] !== 'CORRIGIVEL', 'respeitar limite de camadas');
$inicioChave = strpos($conteudo, 'function chave_tabela(');
// strpos recebe a quebra real, sem depender de expressoes regulares sobre PHP.
$fimChave = strpos($conteudo, "\n\n/*", $inicioChave);
eval(substr($conteudo, $inicioChave, $fimChave - $inicioChave));
class ResultadoSimulado {
    private $rows;
    function __construct($rows) { $this->rows = $rows; }
    function fetch_assoc() { return array_shift($this->rows); }
}
class BancoSimulado {
    public $rows = array();
    public $consultas = 0;
    function real_escape_string($s) { return addslashes($s); }
    function query($sql) { $this->consultas++; return new ResultadoSimulado($this->rows); }
}
$db = new BancoSimulado();
$DB_NAME = 'fixture';
$cacheChaves = array();
$db->rows = array(array('INDEX_NAME'=>'PRIMARY','COLUMN_NAME'=>'id','SUB_PART'=>null,'IS_NULLABLE'=>'NO'));
verificar(chave_tabela('primaria') === array('id'), 'chave primaria');
$db->rows = array(array('INDEX_NAME'=>'uq','COLUMN_NAME'=>'codigo','SUB_PART'=>null,'IS_NULLABLE'=>'YES'));
verificar(chave_tabela('anulavel') === array(), 'unique anulavel preservado');
$db->rows = array(array('INDEX_NAME'=>'uq','COLUMN_NAME'=>'codigo','SUB_PART'=>'10','IS_NULLABLE'=>'NO'));
verificar(chave_tabela('prefixo') === array(), 'unique parcial preservado');
$db->rows = array(
    array('INDEX_NAME'=>'uq','COLUMN_NAME'=>'a','SUB_PART'=>null,'IS_NULLABLE'=>'NO'),
    array('INDEX_NAME'=>'uq','COLUMN_NAME'=>'b','SUB_PART'=>null,'IS_NULLABLE'=>'NO')
);
verificar(chave_tabela('composta') === array('a','b'), 'chave composta');
$db->rows = array(
    array('INDEX_NAME'=>'uq','COLUMN_NAME'=>'a','SUB_PART'=>null,'IS_NULLABLE'=>'NO'),
    array('INDEX_NAME'=>'uq','COLUMN_NAME'=>null,'SUB_PART'=>null,'IS_NULLABLE'=>null)
);
verificar(chave_tabela('expressao') === array(), 'indice com expressao preservado integralmente');
$db->rows = array();
verificar(chave_tabela('sem_chave') === array(), 'sem chave preservado');
$consultas = $db->consultas;
verificar(chave_tabela('sem_chave') === array() && $db->consultas === $consultas, 'cache inclusive sem chave');
echo "Testes: $total; falhas: $falhas\n";
exit($falhas ? 1 : 0);
