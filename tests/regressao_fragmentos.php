<?php
// Teste offline: nao conecta ao MySQL e nao executa o instalador.
$installer = dirname(__DIR__) . '/instalar_mkauth_acento.sh';
$src = file_get_contents($installer);
if ($src === false || !preg_match("/<<'MKAUTH_PHP'\\n(.*?)\\nMKAUTH_PHP/s", $src, $m)) {
    fwrite(STDERR, "FALHA: heredoc PHP nao encontrado\\n"); exit(1);
}
$php = $m[1];
$tokens = token_get_all($php);
$names = array_fill_keys(array(
    'valido_utf8','cp1252_c1_decode','cp1252_c1_encode','camada',
    'score_mojibake','possui_perda_irreversivel','fragmentos_passo',
    'fragmentos_recuperar','melhor_correcao','melhor_correcao_padrao',
    'melhor_correcao_integral'
), true);
$extracted = 0;
for ($i = 0, $n = count($tokens); $i < $n; $i++) {
    if (!is_array($tokens[$i]) || $tokens[$i][0] !== T_FUNCTION) continue;
    $j = $i + 1;
    while ($j < $n && is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) $j++;
    if ($j >= $n || !is_array($tokens[$j]) || !isset($names[$tokens[$j][1]])) continue;
    $name = $tokens[$j][1];
    $body = ''; $depth = 0; $opened = false;
    for ($k = $i; $k < $n; $k++) {
        $tok = $tokens[$k];
        $v = is_array($tok) ? $tok[1] : $tok;
        $body .= $v;
        if (!is_array($tok) && $v === '{') { $depth++; $opened = true; }
        if (!is_array($tok) && $v === '}') {
            $depth--;
            if ($opened && $depth === 0) break;
        }
    }
    if (!$opened || $depth !== 0) { fwrite(STDERR, "FALHA: extracao de $name\\n"); exit(1); }
    eval($body);
    $extracted++;
    $i = $k;
}
if ($extracted !== count($names)) { fwrite(STDERR, "FALHA: funcoes extraidas $extracted/" . count($names) . "\\n"); exit(1); }
$EXPERIMENTAL_FRAGMENTOS = true;
$tests = 0; $failed = 0;
function check_case($label, $condition) {
    global $tests, $failed;
    $tests++;
    if (!$condition) { $failed++; echo "FALHA: $label\\n"; }
    else echo "OK: $label\\n";
}
check_case('rejeita residuo Jos', preg_match('/[\\x{00C3}\\x{00C2}\\x{00C6}]/u', 'JosÃÃÃâ') === 1);
check_case('rejeita residuo bairro', preg_match('/[\\x{00C3}\\x{00C2}\\x{00C6}]/u', 'Jardim SÃÃÆ') === 1);
check_case('aceita caracteres portugueses comuns', preg_match('/[\\x{00C3}\\x{00C2}\\x{00C6}]/u', 'Rua São Paulo') === 0);
check_case('nao classifica perda U+FFFD como corrigivel', melhor_correcao('PRESTA��O')['status'] !== 'CORRIGIVEL');
check_case('nao classifica perda latin1 como corrigivel', melhor_correcao('PRESTAï¿½ï¿½O')['status'] !== 'CORRIGIVEL');
check_case('funcao experimental presente', function_exists('fragmentos_recuperar'));

// Testes sinteticos de 1 a 7 camadas: sem usar dados de clientes.
// A propriedade de seguranca e: se disser CORRIGIVEL, precisa recuperar
// exatamente a string original, sem alteracao de pontuacao ou de HTML.
$originais = array(
    'Rua São Paulo',
    'Consultório',
    'Gregório Magnani',
    'Conexão 24 horas na fibra',
    'Ação e manutenção',
    'Observação: não utiliza linha telefônica',
    '<b>Conexão</b> 24 horas'
);
$camadasTestadas = 0;
$correcoesExatas = 0;
$preservados = 0;
foreach ($originais as $original) {
    $corrompido = $original;
    for ($nivel = 1; $nivel <= 7; $nivel++) {
        // Simula bytes UTF-8 interpretados incorretamente como Latin1.
        $proximo = @iconv('ISO-8859-1', 'UTF-8', $corrompido);
        if ($proximo === false || $proximo === $corrompido) break;
        $corrompido = $proximo;
        $r = melhor_correcao($corrompido, 16);
        $camadasTestadas++;
        $corrigivel = $r['status'] === 'CORRIGIVEL';
        if ($corrigivel) $correcoesExatas++;
        else $preservados++;
        check_case(
            'roundtrip ' . $nivel . ' camada(s): ' . $original,
            !$corrigivel || $r['texto'] === $original
        );
    }
}
echo "COBERTURA: $camadasTestadas casos; $correcoesExatas correcoes declaradas; $preservados preservados.\n";

// Nunca promover texto com perda de bytes ao estado corrigivel.
foreach (array(
    'PRESTA��O', 'PRESTAï¿½ï¿½O', 'Contrato �', 'Rua �',
    'JosÃÃÃâ', 'MÃÃÆ', 'Jardim SÃÃÆ', 'PrÃÃÃâ'
) as $suspeito) {
    $r = melhor_correcao($suspeito, 16);
    check_case('nao promove perda/residuo: ' . $suspeito, $r['status'] !== 'CORRIGIVEL');
}

echo "RESULTADO: " . ($tests - $failed) . "/$tests\\n";
exit($failed ? 1 : 0);
