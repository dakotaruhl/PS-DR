# Connect to SharePoint
Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/yoursite" -Interactive

# Define list name and base string
$listName = "YourListName"
$baseString = "Childrens Health Medical Center - Plano TX - Enchanted Rock"

# Get all list items
$items = Get-PnPListItem -List $listName -PageSize 1000

# Initialize counter
$counter = 1

# Loop through items and update the custom column
foreach ($item in $items) {
    $newValue = "$baseString ($counter)"
    Set-PnPListItem -List $listName -Identity $item.Id -Values @{CustomTitle = $newValue}
    $counter++
}
