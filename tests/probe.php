<?php
// Runs inside the FPM test pool (tests/pool.conf) and checks that every extension the sites
// need works there, not just that it is listed. One line per check: "ok <name>" or
// "FAIL <name>: <detail>", then "done <ok count>". tests/test-image.sh reads the lines.
// The expected PHP minor comes as ?minor=8.6.

declare(strict_types=1);

// Before any output, or the session cookie cannot be sent.
$sessionStarted = session_start();

$results = [];

function check(string $name, callable $test): void
{
    global $results;
    try
    {
        $detail = $test();
        $results[] = $detail === true ? "ok $name" : "FAIL $name: " . var_export($detail, true);
    }
    catch (Throwable $e)
    {
        $results[] = "FAIL $name: " . get_class($e) . ': ' . $e->getMessage();
    }
}

$minor = (string) ($_GET['minor'] ?? '');

check('version', fn () => str_starts_with(PHP_VERSION, $minor . '.') ?: PHP_VERSION);
check('sapi', fn () => PHP_SAPI === 'fpm-fcgi' ?: PHP_SAPI);
// docker-library/php builds every image from 8.6 on as ZTS (PR #1686), before that NTS.
// (bool): PHP_ZTS is a bool in the 8.4 and 8.5 images (measured), so no strict comparison
// with 0/1.
check('zts', fn () => (bool) PHP_ZTS === version_compare($minor, '8.6', '>=') ?: PHP_ZTS);

check('opcache', function ()
{
    $status = function_exists('opcache_get_status') ? opcache_get_status(false) : false;
    return (is_array($status) && $status['opcache_enabled'] === true) ?: $status;
});

check('session', fn () => ($sessionStarted && session_status() === PHP_SESSION_ACTIVE
    && session_save_path() === '/run/php/tmp') ?: session_save_path());

check('mbstring', fn () => (mb_strtoupper('äöü') === 'ÄÖÜ' && mb_strlen('äöü') === 3) ?: 'wrong result');
check('mbregex', fn () => function_exists('mb_ereg') ?: 'mb_ereg missing');

check('gd', function ()
{
    $info = gd_info();
    foreach (['JPEG Support', 'PNG Support', 'WebP Support'] as $key)
    {
        if (($info[$key] ?? false) !== true)
        {
            return "$key missing";
        }
    }
    $image = imagecreatetruecolor(4, 4);
    foreach (['imagejpeg', 'imagepng', 'imagewebp'] as $writer)
    {
        ob_start();
        $writer($image);
        if (strlen((string) ob_get_clean()) === 0)
        {
            return "$writer wrote nothing";
        }
    }
    return true;
});

check('exif', fn () => function_exists('exif_read_data') ?: 'exif_read_data missing');

check('intl', function ()
{
    $formatted = (new NumberFormatter('de_DE', NumberFormatter::DECIMAL))->format(1234.5);
    return ($formatted === '1.234,5' && Normalizer::normalize("e\u{0301}") === "\u{00e9}") ?: $formatted;
});

check('zip', function ()
{
    $file = tempnam(sys_get_temp_dir(), 'zip');
    $zip = new ZipArchive();
    if ($zip->open($file, ZipArchive::OVERWRITE) !== true)
    {
        return 'open for writing failed';
    }
    $zip->addFromString('a.txt', 'probe');
    $zip->close();
    $zip = new ZipArchive();
    $zip->open($file);
    $content = $zip->getFromName('a.txt');
    $zip->close();
    unlink($file);
    return $content === 'probe' ?: $content;
});

check('mysqli', fn () => class_exists('mysqli') ?: 'class mysqli missing');
check('pgsql', fn () => function_exists('pg_connect') ?: 'pg_connect missing');
check('pdo drivers', function ()
{
    $drivers = PDO::getAvailableDrivers();
    $missing = array_diff(['mysql', 'pgsql', 'sqlite'], $drivers);
    return $missing === [] ?: implode(',', $drivers);
});
check('pdo sqlite', fn () => (new PDO('sqlite::memory:'))->query('select 41 + 1')->fetchColumn() === 42 ?: 'wrong result');

check('sodium', fn () => function_exists('sodium_crypto_secretbox') ?: 'sodium missing');
check('curl', fn () => function_exists('curl_init') ?: 'curl missing');
check('openssl', fn () => defined('OPENSSL_VERSION_TEXT') ?: 'openssl missing');

// The pool's restrictions must hold: these are what keep one site out of another.
check('disable_functions', function ()
{
    $present = array_filter(['exec', 'shell_exec', 'system', 'passthru', 'popen', 'proc_open'], 'function_exists');
    return $present === [] ?: implode(',', $present);
});
check('open_basedir', fn () => @file_get_contents('/etc/passwd') === false ?: 'read /etc/passwd');

check('display_errors', fn () => in_array(ini_get('display_errors'), ['', '0', 'Off', 'off'], true) ?: ini_get('display_errors'));

header('Content-Type: text/plain; charset=UTF-8');
$ok = count(array_filter($results, fn (string $line) => str_starts_with($line, 'ok ')));
echo implode("\n", $results), "\n", "done $ok\n";
