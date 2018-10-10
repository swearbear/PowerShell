$sites = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites
foreach ($site in $sites)
{
	foreach ($subnet in $site.subnets){
	   New-Object PSCustomObject -Property @{
	   'Site' = $site.Name
	   'Subnet' = $subnet; }
	}
}
