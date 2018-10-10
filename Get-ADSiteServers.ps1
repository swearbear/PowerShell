<#
.Synopsis
   Get DC names and IPs by Site
.DESCRIPTION
   Get DC names and IPs by Site
.EXAMPLE
   Get-ADSiteServers.ps1
.EXAMPLE
   Get-ADSiteServers.ps1 -Geocode <GEOCODE ie. ZTHV>
#>

param($Geocode)

if ($Geocode) {$param = @{Geocode = $Geocode}}

function filterSiteInfo ($Geocode) {
    $input |%{
        if ($Geocode) {
            if ($_.Name -match $Geocode){
                $_
            }
        }
        else {
            $_
        }
    }
}

    [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites| filterSiteInfo @param | ForEach-Object {
        foreach ($server in $_.Servers)
        {
            $Geo = $server.Name.Split("-")[0]
                if ($Geo.Length -eq 5) {$Geo = $server.Name.substring(1,4)}
                elseif ($Geo.Length -eq 4) {$Geo = $server.Name.substring(0,4)}
                else { Write-Error "Unexpected geocode length."; continue or exit }
            new-object pscustomobject -Property ([ordered]@{
                #'GeoCode' = $server.Name.Split("-")[0]
                'GeoCode' = $Geo
                'SiteName' = $_.Name
                'ServerDNS' = $server.Name.ToUpper().Replace(".AFNOAPPS.USAF.MIL", "").Replace(".AREA52", "")
                'IPAddress' = (Resolve-DnsName $server).IPAddress
            })
        }
    } |Sort-Object -Property GeoCode |ft -AutoSize



 