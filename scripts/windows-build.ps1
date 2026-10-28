param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $version = ([xml](Get-Content apps/windows/Jieliu.Windows/Jieliu.Windows.csproj -Raw)).Project.PropertyGroup.Version
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid package version' }
    $output = Join-Path 'dist' ('Jieliu-' + $Runtime + '-' + $version)
    dotnet publish apps/windows/Jieliu.Windows -c Release -r $Runtime --self-contained true -p:PublishSingleFile=false -o $output
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
    Copy-Item apps/windows/PORTABLE-README.txt (Join-Path $output 'README.txt')
    Copy-Item ("docs/windows-acceptance-" + $version + ".md") (Join-Path $output 'ACCEPTANCE.txt')
    Copy-Item apps/windows/BACKGROUND-CHECK.cmd (Join-Path $output 'BACKGROUND-CHECK.cmd')
    Copy-Item design/concepts.html (Join-Path $output 'REFERENCE.html')
    Compress-Archive -Path "$output/*" -DestinationPath "$output.zip" -Force
    Write-Host "Portable build: $output.zip (unsigned; Windows validation required)"
} finally { Pop-Location }
