Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com 
#Add a custom template

#extract the site script output from an existing list and write it to a variable
$extracted = Get-SPOSiteScriptFromList -ListUrl "https://enchantedrock-my.sharepoint.com/personal/jmiller_enchantedrock_com/Lists/SAWS%20Action%20Tracker"

#upload a site script that can be used with a list design.
Add-SPOSiteScript -Title "Project Action Tracker Script" -Description "This creates a list for tracking Project Actions. Extracted from JMiller personal OD" -Content $extracted

#Create your list design using the site script ID returned  
  Add-SPOListDesign -Title "Project Action Tracker" -Description "A centralized tool to track, manage, and complete project action items with clear ownership and deadlines." -SiteScripts "<ID from previous step>" -ListColor Orange -ListIcon BullseyeTarget -Thumbnail "https://enchantedrock-my.sharepoint.com/:i:/r/personal/jmiller_enchantedrock_com/Documents/project.jpg"

  #Scope the permissions to a custom template
  Grant-SPOSiteDesignRights 
  -Identity <List design ID to apply rights to> 
  -Principals "nestorw@contoso.onmicrosoft.com" 
  -Rights View

  #Get templates
  Get-SPOListDesign <List design ID>

  #Remove custom templates
  Remove-SPOListDesign <List design ID>
  #Remove assosiated Site Scripts 
  Remove-SPOSiteScript <Site script ID>
