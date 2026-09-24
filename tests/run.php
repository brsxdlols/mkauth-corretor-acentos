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
// R17: perfil total de 256 bytes, sem transliteracao ou descarte.
for ($byte = 0; $byte < 256; $byte++) {
    $decoded = cp1252_c1_decode(chr($byte));
    verificar($decoded !== false && cp1252_c1_encode($decoded) === chr($byte), 'roundtrip byte ' . $byte);
}
foreach (array('Árvore', 'Índice', 'Óleo', 'Único', 'ÁÉÍÓÚ ÀÂÃÇ') as $i => $texto) {
    verificar(melhor_correcao($texto, 16)['texto'] === $texto, 'preservar correto R17 ' . $i);
    foreach (array(1, 2, 4, 8) as $n) {
        $entrada = $texto;
        for ($j = 0; $j < $n; $j++) $entrada = cp1252_c1_decode($entrada);
        $r = melhor_correcao($entrada, 16);
        verificar($r['status'] === 'CORRIGIVEL' && $r['texto'] === $texto, 'C1 texto ' . $i . ' camadas ' . $n);
    }
}
$entrada = 'Á';
for ($j = 0; $j < 16; $j++) $entrada = cp1252_c1_decode($entrada);
$r = melhor_correcao($entrada, 16);
verificar($r['status'] === 'CORRIGIVEL' && $r['texto'] === 'Á', 'C1 dezesseis camadas');
verificar(cp1252_c1_encode("\xC2\x80") === false, 'nao aceitar C1 definido como Latin1');
verificar(cp1252_c1_encode('Ω') === false, 'nao transliterar grego');
verificar(camada("\xC3\x83", 'WINDOWS-1252-PRESERVE-C1') === false, 'nao completar UTF8 truncado');
verificar(melhor_correcao('Árvore João 日本語 😀', 16)['status'] === 'OK', 'preservar texto multilíngue');

// R18: contexto estrito, resto preservado e idempotencia.
foreach (array('1','3','21','999') as $n) {
    foreach (array('Travessa','Rua','Avenida','Alameda') as $via) {
        $original = $n . 'Âª ' . $via . ' João Exemplo';
        $esperado = $n . 'ª ' . $via . ' João Exemplo';
        $r = melhor_correcao($original, 16);
        verificar($r['status']==='CORRIGIVEL' && $r['texto']===$esperado, 'ordinal ' . $n . $via);
        verificar($r['rota']==='ORDINAL-ENDERECO-INICIAL:ISO-8859-1', 'rota ordinal ' . $n . $via);
        verificar(melhor_correcao($esperado,16)['status']==='OK', 'ordinal idempotente ' . $n . $via);
    }
}
foreach (array('1ª Travessa João Exemplo', '3º Andar João', 'João Ângelo', 'Texto literal Âª',
    '<p>3Âª Travessa João Exemplo</p>', 'login=3Âª Travessa João', '0Âª Travessa João',
    '1000Âª Travessa João', '3Âª Andar João', '3Âª Travessa João Ã',
    "3Âª Travessa João\n", '3Âª Travessa João / rota', '3Âª Travessa João 😀',
    "3Âª Travessa João\xEF\xBF\xBD") as $i=>$s) {
    verificar(melhor_correcao($s,16)===melhor_correcao_integral($s,16), 'ordinal fora de escopo ' . $i);
}
verificar(melhor_correcao('3Âª Travessa João',0)['status']!=='CORRIGIVEL','ordinal limite zero');

// R19: dados sinteticos, sem nomes ou documentos de clientes.
function sintese_fragmentos($s, $n) {
    return preg_replace_callback('/[^\x00-\x7f]/u', function($m) use ($n) {
        $v = $m[0]; for ($i=0; $i<$n; $i++) $v = cp1252_c1_decode($v); return $v;
    }, $s);
}
function conferir_prova($original, $result) {
    $s = $original;
    foreach ($result['prova_fragmentos'] as $round) {
        $out=''; $last=0;
        foreach ($round['edicoes'] as $e) {
            if (substr($s,$e['offset_bytes'],strlen($e['antes']))!==$e['antes']) return false;
            $back=$round['encoding']==='WINDOWS-1252-PRESERVE-C1' ? cp1252_c1_decode($e['depois']) : iconv($round['encoding'],'UTF-8',$e['depois']);
            if ($back!==$e['antes']) return false;
            $out.=substr($s,$last,$e['offset_bytes']-$last).$e['depois'];$last=$e['offset_bytes']+strlen($e['antes']);
        }
        $s=$out.substr($s,$last);
    }
    return $s===$result['texto'];
}
$EXPERIMENTAL_FRAGMENTOS = true;
foreach (array('ação','Çã','ÁÉÍÓÚ','“texto” – teste','§ 1º preço € 10') as $i=>$sample) {
    foreach(array(1,2,3,4) as $layers) {
        $expected='João intacto: '.$sample;
        $original='João intacto: '.sintese_fragmentos($sample,$layers);
        $r=melhor_correcao($original,16);
        verificar($r['status']==='CORRIGIVEL' && $r['texto']===$expected, 'fragmentos resultado '.$i.'/'.$layers);
        verificar(isset($r['prova_fragmentos']) && conferir_prova($original,$r), 'fragmentos prova '.$i.'/'.$layers);
        verificar(melhor_correcao($expected,16)['texto']===$expected, 'fragmentos idempotente '.$i.'/'.$layers);
    }
}
$html='<p class="fixo">João <strong>'.sintese_fragmentos('ação “teste”',3).'</strong> 123,45 &amp; fim</p>';
$r=melhor_correcao($html,16);
verificar($r['texto']==='<p class="fixo">João <strong>ação “teste”</strong> 123,45 &amp; fim</p>', 'fragmentos HTML texto');
$attribute='<p title="'.sintese_fragmentos('ação',2).'">João</p>';
verificar(melhor_correcao($attribute,16)===melhor_correcao_padrao($attribute,16),'fragmentos nao altera atributo');
foreach(array('João 日本語 😀','AÇÕES E ÓRGÃOS','3ª Travessa João','<p title="ação">João</p>') as $i=>$s) {
    verificar(melhor_correcao($s,16)['texto']===$s,'fragmentos preservar '.$i);
}
foreach(array("João \xEF\xBF\xBD",'João '.sintese_fragmentos("\xEF\xBF\xBD",3),'João '.sintese_fragmentos('ação',3).' DÃƒÆ’Ã‚') as $i=>$s) {
    verificar(melhor_correcao($s,16)['status']!=='CORRIGIVEL','fragmentos perda/truncamento '.$i);
}
verificar(fragmentos_recuperar('João '.sintese_fragmentos('ação',3),1)===false,'fragmentos limite profundidade');
verificar(fragmentos_recuperar(str_repeat('x',262145),16)===false,'fragmentos limite tamanho');
$EXPERIMENTAL_FRAGMENTOS=false;
$s='João '.sintese_fragmentos('ação',3);
verificar(melhor_correcao($s,16)===melhor_correcao_padrao($s,16),'fragmentos desativado padrao');

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
