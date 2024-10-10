# Pinger
 [Powershell] Runs a ping and tracert and logs the result to 3 log files to catch servers that may have intermittent drops and packet loss.

If you have a server that intermittently drops packets or becomes unresponsive, this can be used in conjunction with a scheduler to ping it occasionally.
The log files provided can then be used for troubleshooting and/or analytical review.

## How To Use
1. Add the server(s) to the $serversToPing array.
2. Set the total number of ping packets you want to send in $serversToPing.
3. Point the log files to be stored somewhere accessible: $logFile, $pingLogFile, $traceLogFile
4. Run the script

## The Log Files
Each log file serves a different purpose, and will contain all historical data of each run that the script has performed.

* **Log File** - This log file is the full log, and provides a more readable format of text to view the different metrics.
* **Ping Log File** - This log file is a csv formatted list of the ping data, and can be used for analytics.
* **Trace Log File** - This log file is a csv formatted list of the tracert data, and can be used for analytics.

## Adding to HTML In-line Table for Email
Configuring an email to skim the last 'x' rows off of the log to email out is also fairly simple to accomplish with a secondary script running:
 ```
$pingLog = 'pathToPingLog.csv'
$pingHeader = (Get-Content -Path $pingLog -First 1).Split(',') #Gets the header of the pingLog
$pingData = Import-Csv -Path $pingLog | Select-Object -Last 10 #Gets the last 10 rows (most recent)
$pingData = @($pingData) #converts to an array to be looped over to dynamically build a table for emailing out
```

Example HTML Email Builder:
```
#Table Header
$emailBody += "<table style='border: 1px solid; border-collapse: collapse;'><tr style='border: 1px solid; padding: 0px 10px;'>"
foreach($head in $pingHeader)
{
    $emailBody += "<th style='border: 1px solid; padding: 0px 10px;'>$($head)</th>"
}
$emailBody += "</tr>"
#write-output $pingData

#Table Data
foreach($dataRow in $pingData)
{
    $emailBody += "<tr style='border: 1px solid;'>"
    #Write-Output $dataRow.GetType()
    foreach($property in $dataRow.PSObject.Properties)
    {
        $value = $property.value
        $emailBody += "<td style='border: 1px solid; padding: 0px 10px;'>$($value.replace('<', '&lt;'))</td>"
    }
    $emailBody += "</tr>"
}

$emailBody += "</table>"
```
Passing this $emailBody object into the Message Body allows you to insert a table into your message body.
Depending on your setup, you may need to create your own eMailer helper that builds out an eMail object to send.
