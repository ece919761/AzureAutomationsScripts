#Disable AzContext inheritence
Disable-AzContextAutosave –Scope Process

#Import your Credential object from the Automation Account
    $SQLServerCred = Get-AutomationPSCredential -Name "AzureLogs"
    #Import the SQL Server Name from the Automation variable.
    $SQL_Server_Name = Get-AutomationVariable -Name "AzureLogs_instance"
    #Import the SQL DB from the Automation variable.
    $SQL_DB_Name = Get-AutomationVariable -Name "AzureLogs_db"
    #Import the Storage account key from the Automation variable.
    $StorageAccountKey = Get-AutomationVariable -Name "azuchautomationStorageKey"
 
 #Logging in to Azure...
      try
    {
        "Logging in to Azure..."
        $tenantId = "f66b6bd3-ebc2-4f54-8769-d22858de97c5"
$clientId = "2cf6bf34-68ca-414b-8ce0-3eda9cef1152"
$clientSecret = Get-AutomationVariable -Name "MailSendForDigitalClientSecret"

$securePassword = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $securePassword

Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId 
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
    
    $ErrorActionPreference = "SilentlyContinue"
      
#Get Current Context
$CurrentContext = Get-AzContext
#get all Subscriptions
$specificSubscriptionIds = @(
    "cc9368da-d5c2-4abe-9fa5-780ff5736d1a"

    # Add more subscription IDs as needed
)

# Get subscriptions
[array]$Subscriptions = Get-AzSubscription
#  | Where-Object { $specificSubscriptionIds -contains $_.Id }

if($Subscriptions)
{
    foreach ($Subscription in $Subscriptions)
    {
        Write-Verbose "Changing to Subscription $($Subscription.Name)" -Verbose
        $Output = $null
        $Context = Set-AzContext -TenantId $Subscription.TenantId -SubscriptionId $Subscription.Id -Force
        $Name     = $Subscription.Name
        $TenantId = $Subscription.TenantId
        $SubId    = $Subscription.SubscriptionId
        [array]$Disks = Get-AzDisk | Where-Object{$_.DiskState -eq "Unattached"}
        if($null -ne $Disks)
        {
            Write-Host "We found a count of $($Disks.Count) unattatched disks in subscription ""$($Subscription.Name)""" -ForegroundColor Yellow
            ###################################################
            #Get az billing usage
            Write-Host "Getting usage details for all resources in this subscription"
            $All_Az_Consumption_Usage_Details = $null
            $All_Az_Consumption_Usage_Details = Get-AzConsumptionUsageDetail

            ###################################################
            #Loop through the consumption details
            Write-Host "Looping through all disks we found"
            foreach($Disk in $Disks)
            {
                Write-Host "Attempting to find a billing details mapped to our disk named ""$($Disk.Name)"""
                $Az_Disk_Consumption_Usage_Details = $null
                $Az_Disk_Consumption_Usage_Details = $All_Az_Consumption_Usage_Details | Where-Object {$_.InstanceId -eq $Disk.Id}
                if($Disk.ManagedBy -eq $null)
                {
                    # store the data into ourput variable
                    $Output=    New-Object -TypeName PSObject -Property @{
                        DiskName    = $Disk.Name
                        ResourceGroup = $Disk.ResourceGroupName
                        Subscription = $subscription.Name
                        SubscriptionID = $subscription.Id
                        ResourceId = $Disk.Id
                        Location = $Disk.Location
                        DiskSize   = $Disk.DiskSizeGB
                        Disk_Cost_PreTaxCost = $Az_Disk_Consumption_Usage_Details | Where-Object {$_.InstanceId -eq $Disk.Id} | Measure-Object -Sum -Property Pretaxcost | Select-Object -ExpandProperty sum
                        Disk_Cost_Currency = $Az_Disk_Consumption_Usage_Details | Select-Object -First 1 | Select-Object -ExpandProperty Currency
                    } | Select-object DiskName, ResourceGroup, Subscription, SubscriptionID, Location, DiskSize, Disk_Cost_PreTaxCost, Disk_Cost_Currency
                    $Date = Get-Date -Format "yyyy-MM-dd"
                    #Export the result into a csv file in storage account
                    $FileName = "OrphanedDisks-$Name-$Date.csv"
                    $Output | Export-CSV "$env:TEMP/$FileName" -Notype -Append

                    # SQL query to execute
                    $Query = "INSERT INTO Azure_OrphanedDisks_Logs (Disk, ResourceId, RG, Subscription,SubscriptionID,DiskSize, Location, Disk_Cost_PreTaxCost, Disk_Cost_Currency,Date) VALUES ('$($Disk.Name)', '$($Disk.Id)' , '$($Disk.ResourceGroupName)','$($Name)', '$($SubId)', '$($Disk.DiskSizeGB)', '$($Disk.Location)', '$($Az_Disk_Consumption_Usage_Details | Where-Object {$_.InstanceId -eq $Disk.Id} | Measure-Object -Sum -Property Pretaxcost | Select-Object -ExpandProperty sum)', '$($Az_Disk_Consumption_Usage_Details | Select-Object -First 1 | Select-Object -ExpandProperty Currency)', GETDATE())"
                    # Execute query
                    # "----- Running SQL Command "
                    invoke-sqlcmd -ServerInstance "$SQL_Server_Name" -Database "$SQL_DB_Name" -Credential $SQLServerCred -Query "$Query" -Encrypt
                    # "`n ----- END SQL Command"
                }
                else
                {
                    Write-Host "Disk is attached"
                }
            }
            $Context = New-AzureStorageContext -StorageAccountName "azuchautomation" -StorageAccountKey "$StorageAccountKey"
            Set-AzureStorageBlobContent -Context $Context -Container "logs" -File "$env:TEMP/$FileName" -Blob "$FileName"

            $Tagname = "PrimarySPOC"
            $Tags = Get-AzTag -ResourceId /Subscriptions/$SubId
            $TagValue = $Tags.properties.TagsProperty.$Tagname
            if($null -ne $TagValue)
            {
                $FileAttachment = $null
                $FileAttachment = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:TEMP/$FileName"))
                $MailRecipient = $TagValue
                $MailSubject = "Orphaned Disks Detected in Azure Subscription named $Name as of $Date"
                $MailContent = "Dear Team,`r`n`r`
                     <p>I hope this message finds you well.</p>`r`n`r`
                     <p>We wanted to bring to your attention that during our routine monitoring of resources in your Azure subscription, we have identified orphaned <b>Disks</b> that are not associated with any active deployments or services. Orphaned resources can potentially lead to unnecessary costs and security risks if left unattended.</p>`r`n`r`
                     <p>To assist in maintaining the efficiency and security of your Azure environment, we highly recommend reviewing and taking appropriate actions regarding these orphaned <b>Disks</b>. You may want to consider the following actions:</P>`r`n`r`
                     <p>1. Resource Cleanup: Review the identified orphaned <b>Disks</b> and determine whether they can be safely deleted or if they are still required. Ensure that you have backed up any necessary data before removing resources.<br>`r`n`r`
                     2. Further Investigation: If you are uncertain about the status or purpose of the identified resources, please reach out to our Azure administrators for further clarification and guidance.<br>`r`n`r`
                     3. Optimization: Consider implementing Azure best practices to avoid similar situations in the future, such as tagging resources for better tracking or implementing automated monitoring for resource usage.`r`n`r`
                     `r`n`r`
                     <p>Please take the necessary steps to address the attached list of orphaned <b>Disks</b> at your earliest convenience to prevent any potential impact on your Azure environment.</p>`r`n`r`
                     `r`n`r`
                     <p>If you have any questions or require assistance regarding this matter, please do not hesitate to contact us at: digitaldecsazurecloud@harman.com</p> `r`n`r`
                     `r`n`r`
                     <p>Thank you for your attention to this issue.</p>`r`n`r`
                     `r`n`r`
                     Best regards,<br> `r`n`r`
                     Azure Cloud Team"
                $MailSender = "AzureReports@harman.com"
                $Filename1="OrphanedDisks-$Name-$Date.csv"

                # Connect to GRAPH API
                $tokenBody = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $clientId
    Client_Secret = $clientSecret
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token" -Method POST -Body $tokenBody
$headers = @{
    "Authorization" = "Bearer $($tokenResponse.access_token)"
    "Content-type"  = "application/json"
}

#Send Mail    
$URLsend = "https://graph.microsoft.com/v1.0/users/$MailSender/sendMail"

 


$BodyJsonsend = @"
                    {
                        "message": {
                          "subject": "$MailSubject",
                          "body": {
                            "contentType": "HTML",
                            "content": "$MailContent"                                                 
                                   },
                           "attachments": [
                                        {
                                         "@odata.type": "#microsoft.graph.fileAttachment",
                                         "name": "$Filename1",
                                         "contentType": "text/plain",
                                         "contentBytes": "$FileAttachment"
                                         }
                                          ],                              
                          "toRecipients": [
                            {
                              "emailAddress": {
                                  "address": "$MailRecipient"
                              }
                            }
                          ],
                          "bccRecipients":[
                              {
                                  "emailAddress": {
                                      "address": "digitaldecsazurecloud@harman.com"
                                  }
                              }
                          ]
                        },
                        "saveToSentItems": "false"
                      }
"@

Invoke-RestMethod -Method POST -Uri $URLsend -Headers $headers -Body $BodyJsonsend
            }
        }
    }
}