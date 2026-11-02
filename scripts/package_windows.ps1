$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$web = Join-Path $root 'apps/mobile/build/web'
$outputDir = Join-Path $root 'deliverables/windows'
$output = Join-Path $outputDir 'Lumairie-Windows-Simulator.zip'
if (-not (Test-Path (Join-Path $web 'index.html'))) {
    throw 'Build Flutter Web before packaging.'
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
if (Test-Path $output) { Remove-Item -LiteralPath $output }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($output, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $entries = @(
        @{ Source = (Join-Path $root 'START_WINDOWS.bat'); Entry = 'START_WINDOWS.bat' },
        @{ Source = (Join-Path $root 'simulator/server.js'); Entry = 'simulator/server.js' },
        @{ Source = (Join-Path $root 'deliverables/README_TESTING.md'); Entry = 'README_TESTING.md' }
    )
    foreach ($file in Get-ChildItem -LiteralPath $web -Recurse -File) {
        $relative = $file.FullName.Substring($web.Length).TrimStart('\', '/') -replace '\\', '/'
        $entries += @{ Source = $file.FullName; Entry = "web/$relative" }
    }
    foreach ($item in $entries) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $item.Source, $item.Entry, [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Output $output
