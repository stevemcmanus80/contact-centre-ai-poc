$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent

$config = Get-Content `
    "$ProjectRoot\config\project.json" `
    | ConvertFrom-Json

$FunctionName = $config.lambda

$Events = Join-Path $ProjectRoot "tests\events"

$Tests = @(
    "check_case_status",
    "request_document",
    "speak_to_adviser"
)

foreach ($Test in $Tests) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Running $Test"
    Write-Host "========================================"

    aws lambda invoke `
        --function-name $FunctionName `
        --payload fileb://"$Events\$Test.json" `
        response.json `
        --cli-binary-format raw-in-base64-out | Out-Null

    $Result = Get-Content response.json | ConvertFrom-Json

    Write-Host ""
    Write-Host "Intent : $($Result.sessionState.intent.name)"
    Write-Host "State  : $($Result.sessionState.intent.state)"
    Write-Host ""
    Write-Host "Response:"
    Write-Host $Result.messages[0].content
}

Remove-Item response.json -ErrorAction Ignore

Write-Host ""
Write-Host "All tests completed."