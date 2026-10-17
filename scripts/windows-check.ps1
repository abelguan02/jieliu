param([switch]$Gui)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    dotnet run --project apps/windows/Jieliu.Checks -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core checks failed' }
    dotnet build apps/windows/Jieliu.Windows -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    dotnet run --project apps/windows/Jieliu.Windows -c Release --no-build -- --render-check
    if ($LASTEXITCODE -ne 0) { throw 'Offscreen Windows rendering checks failed' }
    if ($Gui) {
        dotnet run --project apps/windows/Jieliu.Windows -c Release --no-build -- --self-check
        if ($LASTEXITCODE -ne 0) { throw 'Windows GUI checks failed' }
    }
} finally { Pop-Location }
