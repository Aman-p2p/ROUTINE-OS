$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:5173/')
try { $listener.Start() } catch { exit 1 }
$mime = @{
    '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8'
    '.json'='application/json'; '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'
    '.svg'='image/svg+xml'; '.ico'='image/x-icon'; '.webmanifest'='application/manifest+json'
}
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $localPath = [Uri]::UnescapeDataString($context.Request.Url.LocalPath)
            if ($localPath -eq '/') { $localPath = '/index.html' }
            if ($localPath -eq '/api/sync' -and $context.Request.HttpMethod -eq 'POST') {
                # Only accept writes from the dashboard itself (same origin) and keep the payload small.
                $origin = $context.Request.Headers['Origin']
                if ($origin -and $origin -ne 'http://localhost:5173') { $context.Response.StatusCode = 403; continue }
                if ($context.Request.ContentLength64 -gt 65536) { $context.Response.StatusCode = 413; continue }
                $sr = New-Object IO.StreamReader($context.Request.InputStream, [Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Dispose()
                # Write to a temp file first so the pet never reads a half-written sync.json.
                $tmp = Join-Path $PSScriptRoot 'sync.tmp'
                [IO.File]::WriteAllText($tmp, $body)
                Move-Item -LiteralPath $tmp -Destination (Join-Path $PSScriptRoot 'sync.json') -Force
                $context.Response.StatusCode = 204
                continue
            }
            $relative = $localPath.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
            $file = [IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
                $context.Response.StatusCode = 404
            } else {
                $bytes = [IO.File]::ReadAllBytes($file)
                $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
                $context.Response.Headers.Add('Cache-Control','no-store'); $context.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        } catch {
            try { $context.Response.StatusCode = 500 } catch {}
        } finally {
            try { $context.Response.OutputStream.Close(); $context.Response.Close() } catch {}
        }
    }
} finally { $listener.Stop(); $listener.Close() }
