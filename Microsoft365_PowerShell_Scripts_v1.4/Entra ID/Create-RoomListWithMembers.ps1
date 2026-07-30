function New-ManagedRoomList {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$RoomListPrimarySmtpAddress,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string[]]$Members
    )

    if ($PSCmdlet.ShouldProcess($RoomListPrimarySmtpAddress, "Create room list")) {
        New-DistributionGroup `
            -Name $DisplayName `
            -DisplayName $DisplayName `
            -PrimarySmtpAddress $RoomListPrimarySmtpAddress `
            -RoomList `
            -ErrorAction Stop
    }

    foreach ($Member in $Members) {
        try {
            if ($PSCmdlet.ShouldProcess($Member, "Add to room list $RoomListPrimarySmtpAddress")) {
                Add-DistributionGroupMember `
                    -Identity $RoomListPrimarySmtpAddress `
                    -Member $Member `
                    -ErrorAction Stop
            }

            [PSCustomObject]@{
                Action = "AddRoomListMember"
                Target = $Member
                Status = "Success"
                Error  = $null
            }
        }
        catch {
            [PSCustomObject]@{
                Action = "AddRoomListMember"
                Target = $Member
                Status = "Failed"
                Error  = $_.Exception.Message
            }
        }
    }
}