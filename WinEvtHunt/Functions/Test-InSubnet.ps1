<#
.Synopsis
   Test if an host IP address is part of a given subnet.
.DESCRIPTION
   Test if an host IP address is part of a given subnet.
.EXAMPLE
   Test-InSubnet -Address 10.54.4.11 -Network 10.54.0.0/16
.EXAMPLE
   $IPList | Test-InSubnet -Network 10.54.0.0/255.255.0.0 -PassThru

   Instead of returning true/false, the true evaluations return the passed in object(s).
#>
function Test-InSubnet {
    [CmdletBinding(DefaultParameterSetName='Address')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0,ParameterSetName='Address')]
        [ipaddress[]]$Address,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0,ParameterSetName='RRInstance')]
        [ciminstance[]]$RRInstance,

        [Parameter(Mandatory=$true)]
        [string[]]$Network,

        [switch] $PassThru
    )

    begin
    {
        $IPv4Regex = '(?:(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)\.){3}(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)'
        
        function Convert-IPStringToUInt32 ([string] $ip) {
            # Convert ipv4 address string to UInt32 array
            $a = [uint32[]]$ip.Split('.')
            # Reverse byte order, add values, assign to UInt32
            Write-Output ([uint32](($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]))
        }

        # Process all networks in the -Network parameter and apply their appropriate UInt32 values to an array
        $Subnets = @()
        foreach ($Subnet in $Network)
        {
            if (($Subnet -match "\A(?<IP>${IPv4Regex})\s*/\s*(?<NetworkLength>\d{1,2})\z") -or ("\A(?<IP>${IPv4Regex})[\s/]+(?<SubnetMask>${IPv4Regex})\z"))
            {
                $unetwork = Convert-IPStringToUInt32 -ip $Matches['IP']
                
                if ($Matches['SubnetMask'])
                {
                    $umask = Convert-IPStringToUInt32 -ip $Matches['SubnetMask']
                }
                else
                {
                    $umask = (-bnot [uint32]0) -shl (32 - [int]$Matches['NetworkLength'])
                }
            }
            else
            {
                Write-Error -ErrorAction Stop -Message "Invalid subnet notation."
            }

            $Subnets += @{unetwork=$unetwork;umask=$umask}
        }
    }

    process
    {
        # Parameter sets that match parameter names allow for dynamic calls like this
        foreach ($obj in $PSBoundParameters[$PSCmdlet.ParameterSetName])
        {
            if ($PSCmdlet.ParameterSetName -eq 'RRInstance')
            {
                $ip = $obj.RecordData.IPv4Address.IPAddressToString
            }
            else
            {
                $ip = $obj.IPAddressToString
            }

            $uip = Convert-IPStringToUInt32 -ip $ip

            foreach ($sn in $Subnets)
            {
                # compare ipv4 address to each of the networks in the -Network parameter
                if ($PassThru -and ($sn.unetwork -eq ($sn.umask -band $uip)))
                {
                    Write-Output $obj
                    break # Stop evaluating subnets after the first match
                }
                elseif ($sn.unetwork -eq ($sn.umask -band $uip))
                {
                    Write-Output $true
                    break # Stop evaluating subnets after the first match
                }
            }
        }
    }
}
