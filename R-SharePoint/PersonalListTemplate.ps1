#connect to SharePoint Online
Install-Module -Name Microsoft.Online.SharePoint.PowerShell
#required for PS7
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com 

#extract the site script output from an existing list and write it to a variable
$extracted = Get-SPOSiteScriptFromList -ListUrl "https://enchantedrock-my.sharepoint.com/personal/jmiller_enchantedrock_com/Lists/SAWS%20Action%20Tracker"

#upload a site script that can be used with a list design.
Add-SPOSiteScript -Title "Project Action Tracker Script" -Description "This creates a list for tracking Project Actions. Extracted from JMiller personal OD" -Content $extracted

#Create your list design using the site script ID returned  
Add-SPOListDesign -Title "Project Action Tracker" -Description "A centralized tool to track, manage, and complete project action items with clear ownership and deadlines." -SiteScripts "3ab8b9bb-7532-48ff-86a1-67a864d23ef0" -ListColor Orange -ListIcon BullseyeTarget -Thumbnail "https://enchantedrock-my.sharepoint.com/:i:/r/personal/jmiller_enchantedrock_com/Documents/project.jpg"

  #Scope the permissions to a custom template
  Grant-SPOSiteDesignRights -Identity b00836fe-b009-4b75-9b2e-467553adc7bf -Principals "Jmillerlisttemplateusers" -Rights View

  #Get templates
  Get-SPOListDesign b00836fe-b009-4b75-9b2e-467553adc7bf

  #Remove custom templates
  Remove-SPOListDesign <List design ID>
  #Remove assosiated Site Scripts 
  Remove-SPOSiteScript <Site script ID>
