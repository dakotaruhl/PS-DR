#Connect-Graph -scopes "UserAuthenticationMethod.ReadWrite.All"

$androidAAGuid = "de1e552d-db1d-4423-a619-566b625cdc84"
$iosAAGuid = "90a3ccdf-635c-4729-a248-9b709135078f"

$path = "C:\Users\DakotaRuhl\Downloads\GroupExport.xlsx"
$users = Import-Excel -Path $path
$results = @()
foreach ($user in $users) 
{
    try 
    {
        $fido2Methods = Get-MgUserAuthenticationFido2Method -UserId $user.id -ErrorAction Stop
        foreach ($method in $fido2Methods) 
        {
            if ($method.aaGuid -eq $androidAAGuid)
            {
                $results += [PSCustomObject]@{
                    UserPrincipalName    = $user.userPrincipalName
                    AaGuid               = $method.aaGuid
                    DeviceType           = "Android"
                    AttestationLevel     = $method.AttestationLevel
                    DisplayName          = $method.DisplayName
                    CreatedDateTime      = $method.CreatedDateTime
                    Model                = $method.Model
                    AdditionalProperties = #need to figure out how to store this in a single cell, maybe join with a delimiter? $method.AdditionalProperties -join "; " 
                }
            }
            elseif ($method.aaGuid -eq $iosAAGuid) 
            {
                $results += [PSCustomObject]@{
                    UserPrincipalName    = $user.userPrincipalName
                    AaGuid               = $method.aaGuid
                    DeviceType           = "iOS"
                    AttestationLevel     = $method.AttestationLevel
                    DisplayName          = $method.DisplayName
                    CreatedDateTime      = $method.CreatedDateTime
                    Model                = $method.Model
                    AdditionalProperties = $method.AdditionalProperties -join "; "
                }
            }
            else {
                $results += [PSCustomObject]@{
                    UserPrincipalName = $user.userPrincipalName
                    AaGuid           = $method.aaGuid
                    DisplayName      = $method.DisplayName
                    CreatedDateTime  = $method.CreatedDateTime
                }
            }
        }
    }
    catch 
    {
        Write-Warning "Failed to retrieve FIDO2 methods for user: $($user.userPrincipalName). Error: $_"
    }
}

$resultsPath = "C:\Users\DakotaRuhl\Downloads\FIDO2Results.xlsx"
if (Test-Path -Path $resultsPath)
{
    Remove-Item -Path $resultsPath -Force
}
$results | Export-Excel -Path $resultsPath -AutoSize -WorksheetName "FIDO2Results"