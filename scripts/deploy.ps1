$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==============================="
Write-Host " Contact Centre AI Deployment"
Write-Host "==============================="
Write-Host ""

$ProjectRoot = Split-Path $PSScriptRoot -Parent

$config = Get-Content `
    "$ProjectRoot\config\project.json" `
    | ConvertFrom-Json

$FunctionName = $config.lambda

# Package the Lambda

& "$PSScriptRoot\package.ps1"

$ZipFile = Join-Path $ProjectRoot "lambda.zip"

Write-Host ""
Write-Host "Uploading Lambda..."

aws lambda update-function-code `
    --function-name $FunctionName `
    --zip-file fileb://$ZipFile | Out-Null

Write-Host ""
Write-Host "Waiting for Lambda update..."

do {

    Start-Sleep -Seconds 2

    $Status = aws lambda get-function-configuration `
        --function-name $FunctionName `
        --query "LastUpdateStatus" `
        --output text

    Write-Host "Status: $Status"

} while ($Status -eq "InProgress")

Write-Host ""

if ($Status -eq "Successful") {

    Write-Host "✅ Deployment successful!"

}
else {

    Write-Host "❌ Deployment failed."

}