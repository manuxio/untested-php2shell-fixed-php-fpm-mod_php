<?php
// Minimal FastCGI client: php fcgi.php host:port script [ini] < body
// [ini] is "k=v;k2=v2", sent as PHP_VALUE (or as PHP_ADMIN_VALUE when ADMIN=1 is set).
list(, $addr, $script) = $argv;
$phpValue = isset($argv[3]) ? $argv[3] : '';
$body = stream_get_contents(STDIN);
$ctype = getenv('CTYPE') ?: 'application/x-www-form-urlencoded';

function rec($type, $content, $id = 1) {
	$len = strlen($content);
	return pack('CCnnCx', 1, $type, $id, $len, 0) . $content;
}
function nv($k, $v) {
	$f = function ($l) { return $l < 128 ? chr($l) : pack('N', $l | 0x80000000); };
	return $f(strlen($k)) . $f(strlen($v)) . $k . $v;
}

$params = array(
	'SCRIPT_FILENAME' => "/var/www/html/$script",
	'SCRIPT_NAME' => "/$script",
	'DOCUMENT_ROOT' => '/var/www/html', // needed for FPM to look up .user.ini files
	'REQUEST_METHOD' => $body === '' ? 'GET' : 'POST',
	'CONTENT_TYPE' => $ctype,
	'CONTENT_LENGTH' => (string) strlen($body),
	'SERVER_PROTOCOL' => 'HTTP/1.1',
	'GATEWAY_INTERFACE' => 'CGI/1.1',
	'REMOTE_ADDR' => '127.0.0.1',
	'HTTP_COOKIE' => (string) getenv('COOKIE'),
	'QUERY_STRING' => (string) getenv('QUERY'),
);
if ($phpValue !== '') {
	$params[getenv('ADMIN') ? 'PHP_ADMIN_VALUE' : 'PHP_VALUE'] = str_replace(';', "\n", $phpValue);
}
$p = '';
foreach ($params as $k => $v) {
	$p .= nv($k, $v);
}

$s = stream_socket_client("tcp://$addr", $errno, $errstr, 5);
if (!$s) { fwrite(STDERR, "connect failed: $errstr\n"); exit(2); }
$out = rec(1, pack('nCx5', 1, 0)) . rec(4, $p) . rec(4, '');
foreach (str_split($body, 65535) as $chunk) {
	if ($chunk !== '') $out .= rec(5, $chunk);
}
$out .= rec(5, '');
fwrite($s, $out);

$stdout = $stderr = '';
$ended = false;
while (!feof($s)) {
	$h = fread($s, 8);
	if (strlen($h) < 8) break;
	$r = unpack('Cver/Ctype/nid/nlen/Cpad/Cres', $h);
	$c = $r['len'] ? stream_get_contents($s, $r['len']) : '';
	if ($r['pad']) fread($s, $r['pad']);
	if ($r['type'] == 6) $stdout .= $c;
	elseif ($r['type'] == 7) $stderr .= $c;
	elseif ($r['type'] == 3) { $ended = true; break; }
}
echo $stdout;
if ($stderr !== '') echo "\n[fcgi stderr] $stderr";
echo "\n[request ", $ended ? 'completed' : 'ABORTED (connection closed without END_REQUEST)', "]\n";
