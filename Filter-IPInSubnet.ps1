function Filter-IPInSubnet
{
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='Address')]
        [ipaddress[]]$Address,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='RRInstance')]
        [ciminstance[]]$RRInstance,

        [Parameter(Mandatory=$true)]
        [string[]]$Network
    )

    begin
    {   
        $IPv4Regex = '(?:(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)\.){3}(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)'

        #$network, [int]$subnetlen = $cidr.Split('/')

        $Subnets = @()
        foreach ($Subnet in $Network)
        {
            if (($Subnet -match "\A(?<IP>${IPv4Regex})\s*/\s*(?<NetworkLength>\d{1,2})\z") -or ("\A(?<IP>${IPv4Regex})[\s/]+(?<SubnetMask>${IPv4Regex})\z"))
            {
                #Wait-Debugger
                $a = [uint32[]]$Matches['IP'].Split('.')
                [uint32] $unetwork = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]
                if ($Matches['SubnetMask'])
                {
                    $mask = [uint32[]]$Matches['SubnetMask'].Split('.')
                }
                else
                {
                    $mask = (-bnot [uint32]0) -shl (32 - [int]$Matches['NetworkLength'])
                }
            }
            else
            {
                Write-Error "Invalid subnet notation." -ErrorAction Stop
                return
            }

            $Subnets += @{uNetwork=$unetwork;Mask=$mask}
        }
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'RRInstance')
            {
                $ip = $_.RecordData.IPv4Address.IPAddressToString
            }
            else
            {
                $ip = $Address.IPAddressToString
            }

            $a = [uint32[]]$ip.split('.')
            [uint32] $uip = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

            foreach ($sn in $Subnets)
            {
                if ($unetwork -eq ($mask -band $uip))
                {
                    Write-Output $_
                    break
                }
            }
        }
        catch
        {
            $_
            break
        }
    }
}
