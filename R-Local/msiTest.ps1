#Create temp path if it doesn't exist
New-Item -ItemType Directory -Path "C:\Users\$env:USERNAME\AppData\Local\Temp" -ErrorAction SilentlyContinue | Out-Null

#Download msi installer to the temp path
$sourceUrl = "https://vinedeployments.blob.core.windows.net/software/Marathon/2400/DVR2400_2500_Portal_2_1_Setup.msi"
$destinationPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\DVR2400_2500_Portal_2_1_Setup.msi"
Invoke-WebRequest -Uri $sourceUrl -OutFile $destinationPath

# Install the MSI
msiexec.exe /i $destinationPath /qn /norestart /L*v "C:\Users\$env:USERNAME\AppData\Local\Temp\DVR2400_2500_Portal_2_1_Setup.log" 

#Install .exe?
Start-Process -FIlePath "C:\Users\DakotaRuhl\Downloads\CDM21226_Setup.exe" -ArgumentList "/S" -NoNewWindow -Wait