function Get-TerrainOU {
    param(
        [string]$SiteName,
        [string]$Server,
        [string]$ZoneName
    )
    
    $Site = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites |? Name -eq $SiteName

    $OUs = @()
    #$Site.Subnets
    #Wait-Debugger
    foreach ($net in $Site.Subnets) {
        Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $ZoneName -RRType A |
            ? HostName -ne "@" | Test-InSubnet -Network $net.Name |Select -ExpandProperty HostName |
                Get-ADComputer -ea SilentlyContinue |% {$_.DistinguishedName.Split(',', 2) |Select -Last 1} |
                    Get-ADOrganizationalUnit |Select Name,DistinguishedName |
                        % {if ($OUs -notcontains $_.DistinguishedName) {$OUs += $_.DistinguishedName; $_.DistinguishedName}}
    }

}