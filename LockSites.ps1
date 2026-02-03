Import-Module ImportExcel

$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

$filePath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\Quality\OldDMS.xlsx"
 $Worksheet = "Sheet1"
 $columnName = "URL"
 $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet
 $columnValues = $excelData | Select-Object -ExpandProperty $columnName


foreach ($url in $columnValues) {
    set-pnptenantsite -Url $url -lockstate "readonly"
}

#lockstates "unlock", "readonly", "noaccess"
#set-pnptenantsite "https://enchantedrock.sharepoint.com/sites/MicrosoftSJC02-AllColos" -lockstate "unlock"
#get-pnptenantsite $sitescollections[113].Url | Select-Object lockstate