$ErrorActionPreference = "Stop"

$port = 8080
$hostAddress = "192.168.3.8"
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
$allowedExtensions = @(".html", ".css", ".js", ".png", ".jpg", ".jpeg", ".svg", ".webp", ".json")

function Get-ContentType {
  param([string]$Path)

  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".png" { "image/png" }
    ".jpg" { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".svg" { "image/svg+xml" }
    ".webp" { "image/webp" }
    default { "application/octet-stream" }
  }
}

function Write-Response {
  param(
    [System.Net.Sockets.NetworkStream]$Stream,
    [string]$Status,
    [byte[]]$Body = [byte[]]::new(0),
    [string]$ContentType = "text/plain; charset=utf-8"
  )

  $headers = @(
    "HTTP/1.1 $Status"
    "Content-Type: $ContentType"
    "Content-Length: $($Body.Length)"
    "Connection: close"
    ""
    ""
  ) -join "`r`n"

  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($Body.Length -gt 0) {
    $Stream.Write($Body, 0, $Body.Length)
  }
  $Stream.Flush()
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($hostAddress), $port)
$listener.Start()

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()

    try {
      $stream = $client.GetStream()
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()

      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        $client.Close()
        continue
      }

      while ($true) {
        $headerLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($headerLine)) {
          break
        }
      }

      $parts = $requestLine.Split(' ')
      $method = $parts[0]
      $rawPath = if ($parts.Length -gt 1) { $parts[1] } else { "/" }

      if ($method -ne "GET") {
        Write-Response -Stream $stream -Status "405 Method Not Allowed"
        continue
      }

      $pathOnly = $rawPath.Split('?')[0]
      $requestPath = [System.Uri]::UnescapeDataString($pathOnly.TrimStart('/'))

      if ([string]::IsNullOrWhiteSpace($requestPath)) {
        $requestPath = "index.html"
      }

      $relativePath = $requestPath.Replace('/', '\')
      $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
      $extension = [System.IO.Path]::GetExtension($candidatePath).ToLowerInvariant()

      if (
        -not $candidatePath.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
        $candidatePath -ne (Join-Path $root "index.html")
      ) {
        Write-Response -Stream $stream -Status "403 Forbidden"
        continue
      }

      if ($allowedExtensions -notcontains $extension) {
        Write-Response -Stream $stream -Status "403 Forbidden"
        continue
      }

      if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        Write-Response -Stream $stream -Status "404 Not Found"
        continue
      }

      $body = [System.IO.File]::ReadAllBytes($candidatePath)
      Write-Response -Stream $stream -Status "200 OK" -Body $body -ContentType (Get-ContentType -Path $candidatePath)
    }
    finally {
      $client.Close()
    }
  }
}
finally {
  $listener.Stop()
}
