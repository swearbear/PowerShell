function Test-IPv4AddressInSubnet {
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ipaddress[]]$Address,
        [Parameter(Mandatory=$true)]
        [ipaddress]$Network,
        [Parameter(Mandatory=$true,ParameterSetName='SubnetMask')]
        [ipaddress]$SubnetMask,
        [Parameter(Mandatory=$true,ParameterSetName='NetworkLength')]
        [int]$NetworkLength
    )

    begin {
        if ($NetworkLength) {
            [ipaddress]$SubnetMask = [long]4294967295 -shr (32 - $NetworkLength)
        }
        [byte[]]$NetworkOctets = $Network.GetAddressBytes()
        [byte[]]$MaskOctets = $SubnetMask.GetAddressBytes()
    }

    process {
        foreach ($addr in $Address) {
            [byte[]]$AddressOctets = $addr.GetAddressBytes()
            (($NetworkOctets[0] -band $MaskOctets[0]) -eq ($AddressOctets[0] -band $MaskOctets[0])) -and
            (($NetworkOctets[1] -band $MaskOctets[1]) -eq ($AddressOctets[1] -band $MaskOctets[1])) -and
            (($NetworkOctets[2] -band $MaskOctets[2]) -eq ($AddressOctets[2] -band $MaskOctets[2])) -and
            (($NetworkOctets[3] -band $MaskOctets[3]) -eq ($AddressOctets[3] -band $MaskOctets[3]))
        }
    }
}