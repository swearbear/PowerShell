
$xpath = "*[System[EventID=4624]]"
$path = "C:\Users\1390260888A\Desktop\Archive-WEC-Domain-Controllers-2018-09-01-00-29-54-673.evtx"
$out = wevtutil qe $path /q:$xpath /f:xml /lf /c:100
$r = $out |ForEach-Object {
    if ($_ -match '^<Event\s') {
        $e = $_ -replace "\sxmlns='http://schemas.microsoft.com/win/2004/08/events/event'", '' -replace '\<RenderingInfo\s.*', '</Event>'
        $node = ([xml]$e).SelectSingleNode("*[EventData[Data[@Name='TargetUserName' and (not(contains(text(), '$')))]]]")
        if ($node)
        {
            $ht = [ordered]@{
                TimeCreated = $node.System.TimeCreated.SystemTime
                EventID = $node.System.EventID
                Channel = $node.System.Channel
                Computer = $node.System.Computer
            }
            $i=1
            $Datas = if ($node.EventData.Data) {$node.EventData.Data} else {$node.UserData.Data}
            foreach ($data in $Datas) {
                if ($data.Name)
                {
                    $ht["Data_$($data.Name)"] = $data.'#text'
                }
                else
                {
                    $ht["Data_{0:D2}" -f $i] = $data.'#text'
                    $i++
                }
            }
            [pscustomobject]$ht
        }
    }
}

#$r



<#
$out = wevtutil qe $path /q:$xpath /f:xml /lf
$e = ""
$r = $out |ForEach-Object {
    if ($e -eq "") {
        $e = $e, ($_ -replace "\sxmlns='http://schemas.microsoft.com/win/2004/08/events/event'", '') -join ''
    } elseif ($_ -match '\<\/Event\>$') {
        $e = $e, $_ -join ''
        $xml = [xml]$e
        $node = $xml.SelectSingleNode("*[EventData[Data[@Name='TargetUserName' and (not(contains(text(), '$')))]]]")
        if ($node)
        {
            $ht = [ordered]@{
                TimeCreated = $node.System.TimeCreated.SystemTime
                EventID = $node.System.EventID
                Channel = $node.System.Channel
                Computer = $node.System.Computer
            }
            foreach ($data in $node.EventData.Data) {
                $ht["Data_$($data.Name)"] = $data.'#text'
            }
            foreach ($data in $node.UserData.Data) {
                $ht["Data_$($data.Name)"] = $data.'#text'
            }
            [pscustomobject]$ht
        }
        $e = ""
    } else {
        $e = $e, $_ -join ''
    }
}
#>
