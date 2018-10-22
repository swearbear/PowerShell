function Get-TerrainOU {
    [CmdletBinding()]
    param(
        [string]$SiteName,
        [string]$Server,
        [string]$ZoneName
    )
    
    # Get a matching AD Site
    $sitelist = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites
    $site = $sitelist | Where-Object Name -eq $SiteName
    $OUs = @()

    # This is a doozy of a one-liner, but considering how big certain DNS zones can be,
    # I wanted to keep the evaluations chained so we aren't waiting around for every object
    # to complete each step before begining the next.
    foreach ($net in $site.Subnets) {
        Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $ZoneName -RRType A |
        Where-Object HostName -ne "@" |
        Test-InSubnet -Network $net.Name -PassThru |
        Select-Object -ExpandProperty HostName |
        Get-ADComputer -ErrorAction SilentlyContinue |
        ForEach-Object {
            $_.DistinguishedName.Split(',', 2) |
            Select-Object -Last 1 } |
        Get-ADOrganizationalUnit |
        Select-Object Name,DistinguishedName |
        ForEach-Object {
            if ($OUs -notcontains $_.DistinguishedName)
            {
                $OUs += $_.DistinguishedName
                # return OU dn to verbose stream for visual confirmation of progress
                Write-Verbose $_.DistinguishedName
            }
        }
    }
}
