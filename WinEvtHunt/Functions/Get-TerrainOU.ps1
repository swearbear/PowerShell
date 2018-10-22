function Get-TerrainOU {
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
    foreach ($net in $Site.Subnets) {
        Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $ZoneName -RRType A | <#
        Remove "@" hostnames because these are duplicates for our purposes.
        #> Where-Object HostName -ne "@" | <#
        Use custom function to test whether the A record's ip is in $net.
        #> Test-InSubnet -Network $net.Name | <#
        Drop ResourceRecord object and pass only the hostname as a string value.
        #> Select-Object -ExpandProperty HostName | <#
        Do an AD lookup for a computer object with hostname.  Ignore AD object not found errors.
        #> Get-ADComputer -ErrorAction SilentlyContinue | <#
        Do some stuff in a ForEach-Object function...
        #> ForEach-Object
            {
                # Drop the AD object and pass along only the OU portion of the distinguished name as a string value.
                $_.DistinguishedName.Split(',', 2) | <#
                Use Select-Object to grab indexed positions when possible.  Null checks are built-in.
                #> Select-Object -Last 1
            } | <#
        Get the AD object for the OU from the distinguished name we just grabbed.    
        #> Get-ADOrganizationalUnit | <#
        This select-object shouldn't require explaination.
        #> Select-Object Name,DistinguishedName | <#
        Do some more stuff in a ForEach-Object function...
        #> ForEach-Object
            {
                # Add unique OUs to the OUs array
                if ($OUs -notcontains $_.DistinguishedName)
                {
                    $OUs += $_.DistinguishedName
                    # return OU dn to verbose stream for visual confirmation of progress
                    Write-Verbose $_.DistinguishedName
                }
            }
    }

}