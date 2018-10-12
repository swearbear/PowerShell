function Get-TerrainOU {
    param(
        [string]$SiteName,
        [string]$Server,
        [string]$ZoneName
    )

    $Site = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites |? Name -eq $SiteName

    function Filter-IsInSubnet {
        param(
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='Address')]
            [ipaddress[]]$Address,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='RRInstance')]
            [ciminstance[]]$RRInstance,
            [Parameter(Mandatory=$true)]
            [string]$Network
        )

        begin {
            $IPv4Regex = '(?:(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)\.){3}(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)'
        
            function Convert-IPToBinary
            {
                param(
                    [string] $IP
                )
                $IP = $IP.Trim()
                if ($IP -match "\A${IPv4Regex}\z")
                {
                    try
                    {
                        return ($IP.Split('.') | ForEach-Object { [System.Convert]::ToString([byte] $_, 2).PadLeft(8, '0') }) -join ''
                    }
                    catch
                    {
                        Write-Warning -Message "Error converting '$IP' to a binary string: $_"
                        return $Null
                    }
                }
                else
                {
                    Write-Warning -Message "Invalid IP detected: '$IP'."
                    return $Null
                }
            }
        
            function Get-ProperCIDR
            {
                param(
                    [string] $CIDRString
                )
                $CIDRString = $CIDRString.Trim()
                $o = '' | Select-Object -Property IP, NetworkLength
                if ($CIDRString -match "\A(?<IP>${IPv4Regex})\s*/\s*(?<NetworkLength>\d{1,2})\z")
                {
                    # Could have validated the CIDR in the regex, but this is more informative.
                    if ([int] $Matches['NetworkLength'] -lt 0 -or [int] $Matches['NetworkLength'] -gt 32)
                    {
                        Write-Warning "Network length out of range (0-32) in CIDR string: '$CIDRString'."
                        return
                    }
                    $o.IP = $Matches['IP']
                    $o.NetworkLength = $Matches['NetworkLength']
                }
                elseif ($CIDRString -match "\A(?<IP>${IPv4Regex})[\s/]+(?<SubnetMask>${IPv4Regex})\z")
                {
                    $o.IP = $Matches['IP']
                    $SubnetMask = $Matches['SubnetMask']
                    if (-not ($BinarySubnetMask = Convert-IPToBinary $SubnetMask))
                    {
                        return # warning displayed by Convert-IPToBinary, nothing here
                    }
                    # Some validation of the binary form of the subnet mask, 
                    # to check that there aren't ones after a zero has occurred (invalid subnet mask).
                    # Strip all leading ones, which means you either eat 32 1s and go to the end (255.255.255.255),
                    # or you hit a 0, and if there's a 1 after that, we've got a broken subnet mask, amirite.
                    if ((($BinarySubnetMask) -replace '\A1+') -match '1')
                    {
                        Write-Warning -Message "Invalid subnet mask in CIDR string '$CIDRString'. Subnet mask: '$SubnetMask'."
                        return
                    }
                    $o.NetworkLength = [regex]::Matches($BinarySubnetMask, '1').Count
                }
                else
                {
                    Write-Warning -Message "Invalid CIDR string: '${CIDRString}'. Valid examples: '192.168.1.0/24', '10.0.0.0/255.0.0.0'."
                    return
                }
                # Check if the IP is all ones or all zeroes (not allowed: http://www.cisco.com/c/en/us/support/docs/ip/routing-information-protocol-rip/13788-3.html )
                if ($o.IP -match '\A(?:(?:1\.){3}1|(?:0\.){3}0)\z')
                {
                    Write-Warning "Invalid IP detected in CIDR string '${CIDRString}': '$($o.IP)'. An IP can not be all ones or all zeroes."
                    return
                }
                return $o
            }

            $NetworkAddress = Get-ProperCIDR -CIDRString $Network
            [ipaddress]$SubnetMask = [long]4294967295 -shr (32 - [int]$NetworkAddress.NetworkLength)
            [byte[]]$NetworkOctets = ([ipaddress]$NetworkAddress.IP).GetAddressBytes()
            [byte[]]$MaskOctets = $SubnetMask.GetAddressBytes()
        }

        process {
            try {
                if ($PSCmdlet.ParameterSetName -eq 'RRInstance') {
                    [byte[]]$AddressOctets = $_.RecordData.IPv4Address.GetAddressBytes()
                }
                else {
                    [byte[]]$AddressOctets = $_.GetAddressBytes()
                }
                
                if ((($NetworkOctets[0] -band $MaskOctets[0]) -eq ($AddressOctets[0] -band $MaskOctets[0])) -and
                    (($NetworkOctets[1] -band $MaskOctets[1]) -eq ($AddressOctets[1] -band $MaskOctets[1])) -and
                    (($NetworkOctets[2] -band $MaskOctets[2]) -eq ($AddressOctets[2] -band $MaskOctets[2])) -and
                    (($NetworkOctets[3] -band $MaskOctets[3]) -eq ($AddressOctets[3] -band $MaskOctets[3])))
                {
                    Write-Output $_
                }
            }
            catch {
                $_
                break
            }
        }
    }

    $OUs = @()
    $Site.Subnets
    foreach ($net in $Site.Subnets) {
        Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $ZoneName -RRType A |
            ? HostName -ne "@" |Filter-IsInSubnet -Network $net.Name |Select -ExpandProperty HostName |
                Get-ADComputer |% {$_.DistinguishedName.Split(',', 2) |Select -Last 1} |
                    Get-ADOrganizationalUnit |Select Name,DistinguishedName |
                        % {if ($OUs -notcontains $_.DistinguishedName) {$OUs += $_.DistinguishedName; $_}}
    }
}