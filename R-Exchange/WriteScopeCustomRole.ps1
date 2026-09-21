Connect-ExchangeOnline

New-ManagementScope -Name "Business Central SMBs" -RecipientRestrictionFilter "((RecipientTypeDetails -eq 'SharedMailbox') -and (CustomAttribute1 -eq 'BCSMB'))"

#test recipient filter
Get-Recipient -RecipientPreviewFilter "((RecipientTypeDetails -eq 'SharedMailbox') -and (CustomAttribute1 -eq 'BCSMB'))" `
  -ResultSize Unlimited |
  Select-Object DisplayName,PrimarySmtpAddress,RecipientTypeDetails,CustomAttribute1

New-ManagementRoleAssignment -Role "Mail Recipients" -User "username" -CustomRecipientWriteScope "Business Central SMBs"