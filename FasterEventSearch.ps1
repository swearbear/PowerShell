Measure-Command {
$xpath = "*[System[EventID=4624]]"
$path = ".\logs\Archive-WEC-Domain-Controllers-2018-09-01-00-29-54-673.evtx"
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

}