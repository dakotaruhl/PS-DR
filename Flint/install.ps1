$ExtensionId = "makhkhkpghhmfcbjhoomjgbdiokgbkod"
$SourcePath  = Join-Path $PSScriptRoot "ExtensionFiles"
$DestPath    = "C:\Program Files\EdgeExtensions\$ExtensionId"

# Create destination folder if needed
New-Item -Path $DestPath -ItemType Directory -Force | Out-Null

# Copy extension payload
Copy-Item -Path (Join-Path $SourcePath '*') -Destination $DestPath -Recurse -Force