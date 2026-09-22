<#
  Local bridge for the SEU Run Assistant.
  It exposes only loopback HTTP so the page can request a memory scan without
  using the clipboard as the page-to-helper transport. The scan still copies
  the matched value to the clipboard for a manual fallback.
#>
param(
    [int]$Port = 17864,
    [int]$Loop = 45,
    [int]$Interval = 1
)

$ErrorActionPreference = 'Stop'
$scannerPath = Join-Path $PSScriptRoot 'scan_token.ps1'
if (-not (Test-Path -LiteralPath $scannerPath)) {
    throw "Missing scanner: $scannerPath"
}

. $scannerPath -Library

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TokenBridgeWindow {
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static bool Focus(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return false;
        ShowWindow(hWnd, 9);
        return SetForegroundWindow(hWnd);
    }
}
'@

function Send-RawResponse {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [int]$StatusCode,
        [string]$ContentType,
        [byte[]]$BodyBytes,
        [string]$AllowOrigin = '*'
    )
    $statusText = switch ($StatusCode) {
        200 { 'OK' }
        204 { 'No Content' }
        400 { 'Bad Request' }
        403 { 'Forbidden' }
        404 { 'Not Found' }
        409 { 'Conflict' }
        500 { 'Internal Server Error' }
        502 { 'Bad Gateway' }
        default { 'Error' }
    }
    if ($null -eq $BodyBytes) { $BodyBytes = New-Object byte[] 0 }
    $headers = @(
        "HTTP/1.1 $StatusCode $statusText",
        "Content-Type: $ContentType",
        "Content-Length: $($BodyBytes.Length)",
        "Access-Control-Allow-Origin: $AllowOrigin",
        'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS, HEAD',
        'Access-Control-Allow-Headers: Content-Type, Accept, Authorization, Blade-Auth, blade-requested-with, miniappversion, Tenant-Id',
        'Access-Control-Max-Age: 600',
        'Cache-Control: no-store',
        'Connection: close',
        '',
        ''
    ) -join "`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
    $stream = $Client.GetStream()
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($BodyBytes.Length -gt 0) { $stream.Write($BodyBytes, 0, $BodyBytes.Length) }
    $stream.Flush()
    $stream.Dispose()
    $Client.Dispose()
}

function Send-JsonResponse {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [int]$StatusCode,
        [hashtable]$Payload
    )
    $body = if ($StatusCode -eq 204) { '' } else { $Payload | ConvertTo-Json -Compress }
    $bodyBytes = if ($body.Length -gt 0) { [Text.Encoding]::UTF8.GetBytes($body) } else { New-Object byte[] 0 }
    # The scan endpoint stays restricted to file:// pages, as before.
    Send-RawResponse $Client $StatusCode 'application/json; charset=utf-8' $bodyBytes 'null'
}

function Read-HttpRequest {
    # Reads the full request including the body: the API proxy has to forward
    # JSON, AES-encrypted text/plain and multipart photo uploads verbatim.
    param([System.Net.Sockets.TcpClient]$Client)
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 20000
    $buffer = New-Object byte[] 16384
    $memory = New-Object System.IO.MemoryStream
    $headerEnd = -1
    while ($headerEnd -lt 0 -and $memory.Length -lt 33554432) {
        $count = $stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0) { break }
        $memory.Write($buffer, 0, $count)
        $bytes = $memory.ToArray()
        for ($i = 0; $i -le $bytes.Length - 4; $i++) {
            if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10 -and $bytes[$i + 2] -eq 13 -and $bytes[$i + 3] -eq 10) {
                $headerEnd = $i + 4
                break
            }
        }
    }
    if ($memory.Length -eq 0) { return $null }

    $all = $memory.ToArray()
    if ($headerEnd -lt 0) { $headerEnd = $all.Length }
    $headerText = [Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
    $lines = $headerText.Split("`r`n")
    $requestLine = $lines[0].Split(' ')
    $headers = @{}
    $origin = ''
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line.Length -eq 0) { continue }
        $colon = $line.IndexOf(':')
        if ($colon -lt 1) { continue }
        $name = $line.Substring(0, $colon).Trim()
        $value = $line.Substring($colon + 1).Trim()
        $headers[$name] = $value
        if ($name -ieq 'Origin') { $origin = $value }
    }

    $contentLength = 0
    foreach ($key in $headers.Keys) {
        if ($key -ieq 'Content-Length') { [void][int]::TryParse($headers[$key], [ref]$contentLength) }
    }
    $body = New-Object byte[] 0
    if ($contentLength -gt 0) {
        $body = New-Object byte[] $contentLength
        $have = [Math]::Min($all.Length - $headerEnd, $contentLength)
        if ($have -gt 0) { [Array]::Copy($all, $headerEnd, $body, 0, $have) }
        while ($have -lt $contentLength) {
            $count = $stream.Read($body, $have, $contentLength - $have)
            if ($count -le 0) { break }
            $have += $count
        }
    }

    return @{
        Method  = if ($requestLine.Length -gt 0) { $requestLine[0] } else { 'GET' }
        Target  = if ($requestLine.Length -gt 1) { $requestLine[1] } else { '/' }
        Origin  = $origin
        Headers = $headers
        Body    = $body
    }
}

function Focus-WeChat {
    $names = @('WeChatAppEx', 'Weixin', 'WeChat')
    $process = @(Get-Process -Name $names -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object @{Expression={
            if ($_.ProcessName -eq 'WeChatAppEx') { 0 }
            elseif ($_.ProcessName -eq 'Weixin') { 1 }
            else { 2 }
        }}, ProcessName |
        Select-Object -First 1)
    if ($process.Count -eq 0) { return $false }
    return [TokenBridgeWindow]::Focus($process[0].MainWindowHandle)
}

function Focus-Edge {
    $process = @(Get-Process -Name 'msedge' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*SEU Run Assistant*' } |
        Select-Object -First 1)
    if ($process.Count -eq 0) { return $false }
    return [TokenBridgeWindow]::Focus($process[0].MainWindowHandle)
}

function Test-BladeAuthJwt {
    param([string]$Token)
    if ($Token.Length -lt 80) { return $false }
    try {
        $parts = $Token.Split('.')
        if ($parts.Count -ne 3) { return $false }
        # MemScan stops at the first non-token byte. A JWT can therefore be
        # followed by another ASCII word in the same allocation; require the
        # canonical HS256 segment sizes so that suffix is not accepted as part
        # of the signature (the real token has a 43-character base64url sig).
        $headerPart = $parts[0]
        $payloadPart = $parts[1]
        $signaturePart = $parts[2]
        if ($headerPart.Length -ne 36 -or $signaturePart.Length -ne 43) { return $false }
        if ($signaturePart -notmatch '^[A-Za-z0-9_-]{43}$') { return $false }
        $headerPadding = '=' * ((4 - ($headerPart.Length % 4)) % 4)
        $headerJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($headerPart.Replace('-', '+').Replace('_', '/') + $headerPadding)) | ConvertFrom-Json
        if ($headerJson.alg -ne 'HS256') { return $false }
        $padding = '=' * ((4 - ($payloadPart.Length % 4)) % 4)
        $base64 = $payloadPart.Replace('-', '+').Replace('_', '/') + $padding
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json
        if ($json.iss -eq 'bladex.cn') { return $true }
        if (@($json.aud) -contains 'bladex') { return $true }
        if ($json.token_type -eq 'access_token' -and $json.user_id) { return $true }
    } catch {}
    return $false
}

function Find-BladeAuthToken {
    $names = @('WeChatAppEx', 'Weixin', 'WeChat')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $foundProcess = $false

    for ($round = 1; $round -le $Loop; $round++) {
        $targets = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
        if ($targets.Count -gt 0) { $foundProcess = $true }
        $candidates = @()
        foreach ($process in $targets) {
            $results = [MemScan]::Scan($process.Id, 'eyJ')
            if ($null -eq $results) { continue }
            foreach ($entry in $results) {
                $parts = $entry.Split([char]1)
                $token = $parts[0]
                $context = if ($parts.Length -gt 1) { $parts[1] } else { '' }
                if (-not $seen.Add($token)) { continue }
                $isBladeJwt = Test-BladeAuthJwt $token
                if (-not $isBladeJwt) { continue }
                $payload = $token.Split('.')[1]
                $padding = '=' * ((4 - ($payload.Length % 4)) % 4)
                try {
                    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.Replace('-', '+').Replace('_', '/') + $padding)) | ConvertFrom-Json
                } catch { $claims = $null }
                $candidates += [pscustomobject]@{
                    Token = $token
                    Process = $process.ProcessName
                    Pid = $process.Id
                    Round = $round
                    Exp = if ($claims -and $claims.exp) { [long]$claims.exp } else { 0 }
                    Nbf = if ($claims -and $claims.nbf) { [long]$claims.nbf } else { 0 }
                }
            }
            # 命中即结束本轮：16 个微信进程全扫一遍要 12 秒左右，而同一枚 Token
            # 会同时存在于多个渲染进程，扫完再排exp并没有额外收益。
            if ($candidates.Count -gt 0) { break }
        }
        if ($candidates.Count -gt 0) {
            # Prefer the most recently issued/longest-lived candidate. Length
            # is a deterministic tie-breaker and also avoids accidentally
            # selecting a truncated duplicate from another renderer.
            $selected = $candidates |
                Sort-Object @{Expression={ $_.Exp }; Descending=$true},
                            @{Expression={ $_.Nbf }; Descending=$true},
                            @{Expression={ $_.Token.Length }; Descending=$false} |
                Select-Object -First 1
            return @{ Token = $selected.Token; Process = $selected.Process; Pid = $selected.Pid; Round = $selected.Round }
        }
        if ($round -lt $Loop) { Start-Sleep -Seconds $Interval }
    }

    if (-not $foundProcess) { return @{ Error = 'WeChat process not found. Open WeChat first.'; Code = 409 } }
    return @{ Error = 'Blade-Auth token not found. Open the SEU sports mini-program and trigger a data request, then retry.'; Code = 404 }
}

$script:UpstreamOrigin = 'https://tyxsjpt.seu.edu.cn'
$script:ForwardedHeaders = @(
    'authorization', 'blade-auth', 'blade-requested-with', 'miniappversion',
    'accept', 'tenant-id'
)

function Send-UpstreamResponse {
    # Only paths under /api/ reach here and the host is fixed, so the bridge
    # cannot be used as an open proxy.
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [hashtable]$Request
    )
    $forward = @{}
    $contentType = ''
    foreach ($key in $Request.Headers.Keys) {
        $lower = $key.ToLowerInvariant()
        if ($lower -eq 'content-type') { $contentType = $Request.Headers[$key]; continue }
        if ($script:ForwardedHeaders -contains $lower) { $forward[$key] = $Request.Headers[$key] }
    }

    $arguments = @{
        Uri            = $script:UpstreamOrigin + $Request.Target
        Method         = $Request.Method
        Headers        = $forward
        TimeoutSec     = 60
        UseBasicParsing = $true
    }
    if ($contentType) { $arguments['ContentType'] = $contentType }
    if ($Request.Body.Length -gt 0) { $arguments['Body'] = $Request.Body }

    $status = 502
    $bodyText = ''
    $responseType = 'application/json; charset=utf-8'
    try {
        $response = Invoke-WebRequest @arguments
        $status = [int]$response.StatusCode
        $bodyText = [string]$response.Content
        if ($response.Headers['Content-Type']) { $responseType = [string]$response.Headers['Content-Type'] }
    } catch {
        $webResponse = $_.Exception.Response
        if ($webResponse) {
            try {
                $status = [int]$webResponse.StatusCode
                $bodyText = (New-Object IO.StreamReader($webResponse.GetResponseStream())).ReadToEnd()
                if ($webResponse.ContentType) { $responseType = [string]$webResponse.ContentType }
            } catch {
                $status = 502
                $bodyText = '{"code":502,"success":false,"msg":"bridge could not read the upstream response"}'
            }
        } else {
            $message = ($_.Exception.Message -replace '"', "'")
            $bodyText = '{"code":502,"success":false,"msg":"bridge could not reach tyxsjpt.seu.edu.cn: ' + $message + '"}'
        }
    }
    Write-Host "$($Request.Method) $($Request.Target) -> $status"
    Send-RawResponse $Client $status $responseType ([Text.Encoding]::UTF8.GetBytes($bodyText))
}

$listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Parse('127.0.0.1'), $Port)
$listener.Start()
Write-Host "SEU Run Assistant token bridge listening on http://127.0.0.1:$Port/"
Write-Host 'Keep this window open. Click Extract Token in the web page after opening the mini-program.'

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $request = Read-HttpRequest $client
            if (-not $request) { $client.Dispose(); continue }
            $method = $request.Method
            $target = $request.Target
            $origin = $request.Origin
            $path = ($target -split '\?')[0]
            if ($method -eq 'OPTIONS') {
                Send-RawResponse $client 204 'text/plain; charset=utf-8' (New-Object byte[] 0)
                continue
            }
            # Transparent relay for the mini-program API. It exists because the
            # page cannot call the server directly: the server requires
            # blade-requested-with (and, for uploads, miniappversion) but omits
            # both from its Access-Control-Allow-Headers, so every browser
            # preflight fails and fetch throws "Failed to fetch".
            if ($path -like '/api/*') {
                Send-UpstreamResponse $client $request
                continue
            }
            if ($method -ne 'GET') {
                Send-JsonResponse $client 400 @{ ok = $false; error = 'GET only' }
                continue
            }
            if ($path -eq '/health') {
                Send-JsonResponse $client 200 @{ ok = $true; service = 'seu-run-assistant-token-bridge' }
                continue
            }
            if ($path -ne '/scan') {
                Send-JsonResponse $client 404 @{ ok = $false; error = 'Not found' }
                continue
            }
            if ($origin -and $origin -ne 'null') {
                Send-JsonResponse $client 403 @{ ok = $false; error = 'Only file pages are allowed to call the scan endpoint.' }
                continue
            }

            [void](Focus-WeChat)
            Write-Host "Scan requested; waiting for the mini-program request..."
            $match = Find-BladeAuthToken
            if ($match.Token) {
                Set-Clipboard -Value $match.Token
                [void](Focus-Edge)
                Write-Host "Token found in $($match.Process) on round $($match.Round); copied to clipboard."
                Send-JsonResponse $client 200 @{ ok = $true; token = $match.Token; copied = $true }
            } else {
                Send-JsonResponse $client ([int]$match.Code) @{ ok = $false; error = $match.Error }
            }
        } catch {
            try { Send-JsonResponse $client 500 @{ ok = $false; error = 'Bridge error' } } catch {}
        }
    }
} finally {
    $listener.Stop()
}
