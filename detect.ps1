$ExtensionID = "diffhfjoepmlgklilllnlfpafmlgnpmk"
$Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"

if (Test-Path $Path) {
    $props = Get-ItemProperty $Path
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Value -like "$ExtensionID*") {
            exit 0
        }
    }
}

exit 1