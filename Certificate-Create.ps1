$Subject = "CN=DakotaPersonalCert" 

$Cert = New-SelfSignedCertificate `
    -Subject $Subject `
    -KeySpec Signature `
    -KeyExportPolicy Exportable `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(2)

$Cert

$Cert.Thumbprint

Export-Certificate `
    -Cert $Cert `
    -FilePath "C:\Temp\$($Subject.Replace('CN=','')).cer"