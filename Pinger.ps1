# Written By: Christopher Roelle
# 2024-10-10

clear

#Place the server name(s) in this array.
$serversToPing = @("")
$totalPackets = 10 #How many ping packets to send.

#Point these where you want the logs to store.
#Files will dynamically create themselves if they dont exist.
#New data will append to the files.
$logFile = ".\fullLog.log"
$pingLogFile = ".\pingLog.csv"
$traceLogFile = ".\traceLog.csv"

# DO NOT MODIFY
$hostInfo = @{
    Host = ''
    IPv4 = ''
    Subnet = ''
    Gateway = ''
}

$fullResults = @()
$timeStamp = Get-Date

# FUNCTIONS
function GetCurMachineInfo()
{
    Write-Output("`nGetting current machine info...")
    $hostInfo['Host'] = Invoke-Expression -Command "hostname"

    #IP Config
    $ipConfigResults = Invoke-Expression -Command "ipconfig"
    $hostInfo['IPv4'] = (($ipConfigResults | select-string "ipv4") -replace 'IPv4 Address[\.\s:]*', '').Trim()
    $hostInfo['Subnet'] = (($ipConfigResults | select-string "subnet") -replace 'Subnet Mask[\.\s:]*', '').Trim()
    $hostInfo['Gateway'] = (($ipConfigResults | select-string "gateway") -replace 'Default Gateway[\.\s:]*', '').Trim()
    Write-Output("`tComplete!`n")
}

function PingServer()
{
    param (
        [string] $server 
    )

    Write-Output("Contacting $($server)...")

    # ==== PING ====
    Write-Host "`tPing: $($server)" -NoNewline
    
    # Start the job to ping the server
    $pingJob = Start-Job -ScriptBlock {
        param($server, $totalPackets)
        Invoke-Expression -Command "ping /n $totalPackets $server" | Out-String
    } -ArgumentList $server, $totalPackets

    # Display the progress
    $waits = 0
    while((Get-Job -Id $pingJob.Id).State -ne 'Completed')
    {
        Start-Sleep -Milliseconds 250

        # Increment the dots based on progress to the CLI
        $waits++
        if($waits % 3 -eq 0 -and $waits -le 15) {
            Write-Host '.' -NoNewline
        }
    }

    #Get the results
    $pingOutput = Receive-Job -Id $pingJob.Id

    # Clean up job
    Remove-Job -Id $pingJob.Id
    Write-Host 'Complete!'

    # ==== PING ====
    Write-Host "`tTracert: $($server)" -NoNewline
    
    # Start the job to tracert the server
    $traceJob = Start-Job -ScriptBlock {
        param($server, $totalPackets)
        Invoke-Expression -Command "tracert $server" | Out-String
    } -ArgumentList $server

    # Display the progress
    $waits = 0
    while((Get-Job -Id $traceJob.Id).State -ne 'Completed')
    {
        Start-Sleep -Milliseconds 250

        # Increment the dots based on progress to the CLI
        $waits++
        if($waits % 3 -eq 0 -and $waits -le 15) {
            Write-Host '.' -NoNewline
        }
    }

    #Get the results
    $traceOutput = Receive-Job -Id $traceJob.Id

    # Clean up job
    Remove-Job -Id $traceJob.Id
    Write-Host 'Complete!'

    #Merge the output
    $combinedOutput = $pingOutput + '' + $traceOutput
    
    Write-Output("`tComplete!`n")

    ParseOutput -server $server -textToParse $combinedOutput
    
}

function ParseOutput()
{
    param(
        [string] $server,
        [string] $textToParse
    )

    Write-Output("Parsing data for $($server)...")

    $pingData = @{
        Server = ''
        Alias = ''
        IP = ''
        Bytes = @()
        Time = @()
        TTL = @()
        NumSent = 0
        NumReceived = 0
        NumLost = 0
        MinTime = 0
        MaxTime = 0
        AvgTime = 0
        Hops = @()
    }

    $pingData.Server = $server

    # Split the text by lines
    $lines = $textToParse -split "`n"
    $inTracert = $false

    foreach($line in $lines)
    {
        # Extract IP and any alias
        if(!$inTracert -and $line -match 'Pinging\s+([\w\.-]+)\s+\[(\d{1,3}(\.\d{1,3}){3})\]')
        {
            # Check if the alias differs, if so, record it
            if($matches[1].toLower() -ne $server.ToLower())
            {
                $pingData.Alias = $matches[1]
            }
            else {
                $pingData.Alias = ''
            }

            $pingData.IP = $matches[2] # IP is in second capture group
        }
        # Extract bytes/Time/TTL foreach reply
        elseif(!$inTracert -and $line -match 'Reply from (\d{1,3}(\.\d{1,3}){3}): bytes=(\d+) time=(\d+)ms TTL=(\d+)') 
        {
            $pingData.Bytes += [int]$matches[3]
            $pingData.Time += "$($matches[4])ms"
            $pingData.TTL += [int]$matches[5]
        }
        # Extract bytes/Time/TTL foreach reply that timed out
        elseif(!$inTracert -and $line -match 'Request timed out.') 
        {
            $pingData.Bytes += "Timed Out"
            $pingData.Time += "Timed Out"
            $pingData.TTL += "Timed Out"
        }
        #Extract packet stats
        elseif(!$inTracert -and $line -match 'Packets: Sent = (\d+), Received = (\d+), Lost = (\d+)')
        {
            $pingData.NumSent = [int]$matches[1]
            $pingData.NumReceived = [int]$matches[2]
            $pingData.NumLost = [int]$matches[3]
        }
        #Extract round-trip times
        elseif(!$inTracert -and $line -match 'Minimum = (\d+)ms, Maximum = (\d+)ms, Average = (\d+)ms')
        {
            $pingData.MinTime = "$($matches[1])ms"
            $pingData.MaxTime = "$($matches[2])ms"
            $pingData.AvgTime = "$($matches[3])ms"
        }
        #Detect if we have hit the tracert data
        elseif($line -match 'Tracing route to ([\w\.-]+) \[(\d{1,3}(\.\d{1,3}){3})\]')
        {
            $inTracert = $true
            continue
        }
        #Extract the hops from the tracert
        elseif($inTracert -and $line -match '\s*\d+\s+([\d*<]+)\s+ms\s+([\d*<]+)\s+ms\s+([\d*<]+)\s+ms\s+((\d{1,3}(\.\d{1,3}){3}))')
        {
            $hopIP = $matches[4]
            $t1 = "$($matches[1])"
            $t2 = "$($matches[2])"
            $t3 = "$($matches[3])"

            $times = @($t1, $t2, $t3)

            #Add the hop to the Hops array
            $pingData.Hops += @{
                IP = $hopIP
                Times = $times
            }
        }
        # Detect the end of the tracert data
        elseif ($line -match 'Trace complete') {
            $inTraceroute = $false
        }
        # Detect if server cant be pinged
        elseif($line -match "Ping request could not find host $($server). Please check the name and try again.")
        {
            $pingData.IP = "Could not find host!"
        }
        # Detect if server cant be traced
        elseif($line -match "Unable to resolve target system name $($server).")
        {
            $hopIp = "Unable to resolve!"
            $t1 = '-1'
            $t2 = '-1'
            $t3 = '-1'
            $times = @($t1, $t2, $t3)


            $pingData.Hops += @{
                IP = $hopIP
                Times = $times
            }
        }

        
    }

    #Add the object to fullResults
    $global:fullResults += $pingData

    Write-Output("`tComplete!`n")

}

function WriteToFile()
{

    param(
        [String] $path,
        [String] $data
    )

    try
    {
        Add-Content -Path $path -Value $data
    }
    catch
    {
        Write-Error($_)
        exit(1)
    }
}

function OutputReport()
{
    Write-Output("Outputting file...")

    #Check output file exists
    if(!(test-path -Path $global:logFile))
    {
        Write-Output("`tCreating Full Log File...")
        New-Item -Path $logFile | Out-Null
        Write-Output("`t`tComplete!")
    }

    #Check Ping file exists
    if(!(test-path -Path $global:pingLogFile))
    {
        Write-Output("`tCreating Ping Log File...")
        New-Item -Path $pingLogFile | Out-Null
        WriteToFile -path $pingLogFile -data ("Timestamp,Pinged Server,Pinged Alias,Pinged IP,"`
        + "Host,Host IP,Host Subnet,Host Gateway,"`
        + "Rqst,Bytes Sent,Time Taken,TTL,"`
        + "Min Time,Max Time,Avg Time,"`
        + "Sent,Rcvd,R%,Lost,L%"
        )
        Write-Output("`t`tComplete!")
    }

    #Check Trace file exists
    if(!(test-path -Path $global:traceLogFile))
    {
        Write-Output("`tCreating Tracert Log File...")
        New-Item -Path $traceLogFile | Out-Null
        WriteToFile -path $traceLogFile -data ("Timestamp,Traced Server,Traced Alias,Traced IP,"`
        + "Host,Host IP,Host Subnet,Host Gateway,"`
        + "Hop,Hop IP,Time1,Time2,Time3"
        )
        Write-Output("`t`tComplete!")
    }

    #Output the header
    WriteToFile -Path $global:logFile -data "============================================"
    WriteToFile -Path $global:logFile -data "START - $($timeStamp)"
    WriteToFile -Path $global:logFile -data "============================================`n"

    WriteToFile -Path $global:logFile -data "Host Data"
    WriteToFile -Path $global:logFile -data "======================="
    WriteToFile -Path $global:logFile -data "Name: $($hostInfo.Host)"
    WriteToFile -Path $global:logFile -data "IPv4: $($hostInfo.IPv4)"
    WriteToFile -Path $global:logFile -data "Subnet: $($hostInfo.Subnet)"
    WriteToFile -Path $global:logFile -data "Gateway: $($hostInfo.Gateway)"

    foreach($result in $fullResults)
    {
        $rcvdPercent = if($result.NumSent -gt 0){"$(($result.NumReceived / $result.NumSent) * 100)%"} else { "0%" }
        $lostPercent = if($result.NumSent -gt 0){"$(($result.NumLost / $result.NumSent) * 100)%"} else { "100%" }

        WriteToFile -Path $global:logFile -data "`nServer Data"
        WriteToFile -Path $global:logFile -data "======================="
        WriteToFile -Path $global:logFile -data "Server: $($result.Server)"
        WriteToFile -Path $global:logFile -data "Alias: $($result.Alias)"

        #Ping Data
        #Prep PingData for table formatting
        $pingData = for($i = 0; $i -lt $totalPackets; $i++)
        {
            [pscustomobject]@{
                Rqst = "#$($i + 1)"
                Bytes = "$($result.Bytes[$i])"
                Time = "$($result.Time[$i])"
                TTL = "$($result.TTL[$i])"
            }

            #Build the Ping report CSV
            WriteToFile -path $global:pingLogFile `
                    -data ("$($timeStamp),"`
                            + "$($result.Server), $($result.Alias), $($result.IP),"`
                            + "$($HostInfo.Host), $($HostInfo.IPv4), $($HostInfo.Subnet), $($HostInfo.Gateway),"`
                            + "#$($i + 1), $($result.Bytes[$i]), $($result.Time[$i]), $($result.TTL[$i]),"`
                            + "$($result.MinTime), $($result.MaxTime), $($result.AvgTime),"`
                            + "$($result.NumSent), $($result.NumReceived), $($rcvdPercent),"`
                            + "$($result.NumLost), $($lostPercent),"
                            )
        }

        $formattedTable1 = $pingData | Format-Table -AutoSize | Out-String

        
        
        WriteToFile -Path $global:logFile -data $formattedTable1

        WriteToFile -Path $global:logFile -data "Packets Sent: $($result.NumSent)"
        WriteToFile -Path $global:logFile -data "Packets Rcvd: $($result.NumReceived)`t[$($rcvdPercent)]"
        WriteToFile -Path $global:logFile -data "Packets Lost: $($result.NumLost)`t[$($lostPercent)]"

        WriteToFile -Path $global:logFile -data "`nMinimum Time: $($result.MinTime)"
        WriteToFile -Path $global:logFile -data "Maximum Time: $($result.MaxTime)"
        WriteToFile -Path $global:logFile -data "Average Time: $($result.AvgTime)"

        # Tracert data
        #Prep PingData for table formatting
        $trcData = for($i = 0; $i -lt $result.Hops.Count; $i++)
        {
            [pscustomobject]@{
                Rqst = "#$($i + 1)"
                HopIP = "$($result.Hops[$i].IP)"
                Time1 = if($result.Hops[$i].Times[0] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[0])ms"}
                Time2 = if($result.Hops[$i].Times[1] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[1])ms"}
                Time3 = if($result.Hops[$i].Times[2] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[2])ms"}
            }

            #Build the Trace report CSV
            WriteToFile -path $global:traceLogFile `
                    -data ("$($timeStamp),"`
                            + "$($result.Server), $($result.Alias), $($result.IP),"`
                            + "$($HostInfo.Host), $($HostInfo.IPv4), $($HostInfo.Subnet), $($HostInfo.Gateway),"`
                            + "#$($i + 1), $($result.Hops[$i].IP),"`
                            + "$(if($result.Hops[$i].Times[0] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[0])ms"}),"`
                            + "$(if($result.Hops[$i].Times[1] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[1])ms"}),"`
                            + "$(if($result.Hops[$i].Times[2] -eq '*'){ 'Lost' }else{"$($result.Hops[$i].Times[2])ms"}),"
                            )
        }

        $formattedTable2 = $trcData | Format-Table -AutoSize | Out-String
        
        WriteToFile -Path $global:logFile -data $formattedTable2
        
    }

    #Output the footer
    WriteToFile -Path $global:logFile -data "`n============================================"
    WriteToFile -Path $global:logFile -data "END - $($timeStamp)"
    WriteToFile -Path $global:logFile -data "============================================`n"

    Write-Output("`tComplete!`n")
}

# BEGIN PROCESSING
if($serversToPing.count -gt 0)
{
    # Get the current machine info
    GetCurMachineInfo


    foreach($server in $serversToPing)
    {
        PingServer -server $server
    }

    OutputReport
}
else {
    Write-Output("No servers in list!")
}

Write-Output("Processing Complete!")