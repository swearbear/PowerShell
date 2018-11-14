# proxy cmdlets

# [math] extension methods

function Iqr ([double[]]$set) {
    [array]::Sort($set)
    if ($set.Length % 2 -eq 1) {
        # odd
        $s = ($set.Length - 1) / 2
        $s1 = $set[0..($s-1)]
        $s2 = $set[($s+1)..$set.GetUpperBound(0)]
    }
    else {
        $s = $Set.Length / 2
        $s1 = $set[0..($s-1)]
        $s2 = $set[$s..$set.GetUpperBound(0)]
    }
    $md1 = Median($s1)
    $md2 = Median($s2)
    $s1 -join ','
    $s2 -join ','
    $md1
    $md2
    $md2 - $md1
}

function Mean([double[]]$set) {
    $set |measure -Average |select -exp Average
} New-Alias Average Mean

function Median([double[]]$set) {
    if ($set.Length%2 -eq 1) {$set[(($set.Length-1)/2)]}
    else {
        $medset = (($set.Length/2)-1 |% {$set[$_..($_+1)]})
        ($medset[0]+$medset[1])/2
    }
}

function Range ([double[]]$set) {
    $results = $set |measure -Maximum -Minimum
    $results.Maximum - $results.Minimum
}

function Max ([double[]]$set) {
    $set |measure -Maximum |select -ExpandProperty Maximum
}

function Min ([double[]]$set) {
    $set |measure -Minimum |select -ExpandProperty Minimum
}

function Variance ([double[]]$set) {
    $mean = ($set |measure -Average).Average
    ($set |% {($_-$mean) * ($_-$mean)} |measure -Sum).Sum / $set.Length
}

function StdDev ([double[]]$variance) {
    if ($variance.Length -gt 1) {
        # assume that variance hasn't be calculated yet
        [math]::Sqrt((Variance($variance)))
    }
    else {
        [math]::Sqrt($variance[0])
    }
}
