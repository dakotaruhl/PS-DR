# MOCChildTools

Reusable MOC child-script helper module.

## Files

- `MOCChildTools.psm1`: module implementation
- `MOCChildTools.psd1`: module manifest
- `Example-MOCChildScript.ps1`: minimal child-script pattern

## Install pattern

Put `MOCChildTools.psm1` and `MOCChildTools.psd1` in the same folder as the child script, or in a shared MOC module folder.

```powershell
Import-Module (Join-Path $PSScriptRoot 'MOCChildTools.psd1') -Force -DisableNameChecking
```

Then initialize run state at the top of the child script:

```powershell
$Run = Initialize-MOCChildRun `
    -ScriptPath $PSCommandPath `
    -ScriptRoot $PSScriptRoot `
    -ReportsRoot $ReportsRoot `
    -RunFolderPrefix 'Custom-Report' `
    -TotalSteps 4 `
    -UseExistingSession:$UseExistingSession `
    -DoNotOpenOutput:$DoNotOpenOutput
```

## Important refactor notes

- The module owns shared state in `$script:MOCChildState`.
- Child scripts should call `Get-MOCChildState` when they need the latest paths after initialization.
- `Assert-MOCGraphPermission` is preserved. Use `Import-Module -DisableNameChecking` to suppress unapproved verb warnings.
- `Assert-ImportExcelAvailable` is preserved. Use `Import-Module -DisableNameChecking` to suppress unapproved verb warnings.
- The sample child script keeps MOC parent ownership boundaries intact.
- Function names are preserved rather than renamed to approved PowerShell verbs.
