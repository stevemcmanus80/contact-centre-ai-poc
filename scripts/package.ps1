$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "Packaging Lambda..."

$ProjectRoot = Split-Path $PSScriptRoot -Parent

$LambdaFolder = Join-Path $ProjectRoot "lambda\lex_orchestrator"

$ZipFile = Join-Path $ProjectRoot "lambda.zip"

if (Test-Path $ZipFile) {
    Remove-Item $ZipFile
}

Compress-Archive `
    -Path "$LambdaFolder\*" `
    -DestinationPath $ZipFile `
    -Force

Write-Host ""
Write-Host "Lambda package created:"
Write-Host $ZipFile