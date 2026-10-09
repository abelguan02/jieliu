param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $output = Join-Path 'dist' ('Jieliu-' + $Runtime)
    dotnet publish apps/windows/Jieliu.Windows -c Release -r $Runtime --self-contained true -p:PublishSingleFile=false -o $output
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
    Copy-Item apps/windows/PORTABLE-README.txt (Join-Path $output 'README.txt')
    Compress-Archive -Path "$output/*" -DestinationPath "$output.zip" -Force
    Write-Host "Portable build: $output.zip (unsigned; Windows validation required)"
} finally { Pop-Location }
