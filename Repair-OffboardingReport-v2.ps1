#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Path = '.\Get-AzureEntraOffboardingReport-v2.ps1'
)

$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$content = Get-Content -LiteralPath $resolvedPath -Raw
$backupPath = "$resolvedPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -Force

$newFunction = @'
function Get-AllGraphPages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject

        $valueProperty = $response.PSObject.Properties['value']
        if ($null -ne $valueProperty) {
            foreach ($item in @($valueProperty.Value)) {
                if ($null -ne $item) {
                    $items.Add($item) | Out-Null
                }
            }
        }
        elseif ($null -ne $response) {
            $items.Add($response) | Out-Null
        }

        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        if ($null -ne $nextLinkProperty -and -not [string]::IsNullOrWhiteSpace([string]$nextLinkProperty.Value)) {
            $next = [string]$nextLinkProperty.Value
        }
        else {
            $next = $null
        }
    }

    return @($items)
}
'@

$pattern = '(?ms)^function Get-AllGraphPages \{.*?^\}\r?\n\r?\nfunction Resolve-DirectoryObjectName'
if ($content -notmatch $pattern) {
    throw 'Could not locate Get-AllGraphPages. No changes were made.'
}

$content = [regex]::Replace(
    $content,
    $pattern,
    $newFunction + "`r`nfunction Resolve-DirectoryObjectName",
    1
)

Set-Content -LiteralPath $resolvedPath -Value $content -Encoding utf8

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $resolvedPath,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    Copy-Item -LiteralPath $backupPath -Destination $resolvedPath -Force
    $messages = $parseErrors | ForEach-Object Message
    throw "Patched file failed parsing and was restored. $($messages -join ' | ')"
}

Write-Host "Patched: $resolvedPath" -ForegroundColor Green
Write-Host "Backup:  $backupPath" -ForegroundColor DarkGray
Write-Host 'Run the report again. For the Granite run, add SkipExchange = $true to the parameter hashtable.' -ForegroundColor Yellow
