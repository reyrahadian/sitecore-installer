Function ReadConfigFile($currentDirectory){
    $configFile = $currentDirectory+'\sitecore-installer.config'
	return [xml](cat $configFile)
}

Function ExtractDmsZipFile($file,$websiteFolderPath,$databaseFolderPath){
	$shell = new-object -com shell.application
	$zip = $shell.Namespace($file)
	foreach($item in $zip.items()){       
        if($item.Name.EndsWith("config")){
            $websiteIncludeFolderPath = $websiteFolderPath+"app_config\include\" 
            $shell.Namespace($websiteIncludeFolderPath).copyhere($item, 0x10)           
        }
        else{            
            $shell.Namespace($databaseFolderPath).copyhere($item, 0x10)   
        }		
	}
}

Function ExtractCmsZipFile($file,$destination){
	$shell = new-object -com shell.application
	$zip = $shell.Namespace($file)
	foreach($item in $zip.items()){
        foreach($childItem in $item.GetFolder.items()){
            $shell.Namespace($destination).copyhere($childItem, 0x10)
        }		
	}
}

Function ThrowErrorIfPathIsInvalid($path){
    if(!(Test-Path $path)){
        throw $($path) + " is an invalid path"
    }
}

Function EnsureFolderExist($path){
    if(!(Test-Path $path)){
        New-Item $path -ItemType directory
    }
}

Function ThrowIfDbInstanceDoesNotExist($instanceName){
    $found = $false
    foreach($instance in (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances){
        if($instance.ToLowerInvariant() -eq $instanceName.ToLowerInvariant()){
            $found = $true
        }
    }
    if(!$found){
        throw "Db instance "+$instanceName+" does not exist"
    }
}

Function GetDbServerInstance($sqlServerInstanceName){
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    $databaseFullInstancePath = "(local)\"+$sqlServerInstanceName
    $server = New-Object('Microsoft.SqlServer.Management.Smo.Server') $databaseFullInstancePath

    return $server
}

Function AttachDatabaseFile($server,$databaseName,$databaseFilePath){
    DetachDatabaseIfExist $server $databaseName

    $sc = new-object System.Collections.Specialized.StringCollection
    $sc.Add($databaseFilePath+".mdf")
    $sc.Add($databaseFilePath+".ldf")
    $server.AttachDatabase($databaseName, $sc)

    SetDatabaseOwner $server $databaseName
}

Function DetachDatabaseIfExist($server,$databaseName){
    $found = $false
    foreach($database in $server.Databases){
        if($database.Name -eq $databaseName){
            $found = $true
        }
    }    

    if($found){
        $server.DetachDatabase($databaseName,$false)
    }
}

Function SetDatabaseOwner($server,$databaseName){
    $db = New-Object Microsoft.SqlServer.Management.Smo.Database
    $db = $server.Databases.Item($databaseName)

    $db.SetOwner("user", $TRUE)
}

Function CreateDbUserIfNotExist($server,$username,$password){
    $login = $server.Logins[$username]
    if($login -eq $null){
        $login = new-object Microsoft.SqlServer.Management.Smo.Login($server.Name, $username)
        $login.LoginType = 'SqlLogin'
        $login.PasswordPolicyEnforced = $false
        $login.PasswordExpirationEnabled = $false
        $login.Create($password)
    }
}

Function TearDownExistingInstallation($config){
    #stop iis application pool
    $hostName = $config.configuration.IIS.HostName.value
    $webApp = Get-WebApplication $hostName
    if(!($webApp -eq $null)){
        Remove-WebAppPool $hostName 
    }
    $website = Get-Website $hostName
    if(!($website -eq $null)){
        Remove-IisWebsite $hostName
    }    

    #detach database
    $projectName = $config.configuration.Project.value
    $sqlServerInstanceName = $config.configuration.Database.TargetInstance.value
    $server = GetDbServerInstance $sqlServerInstanceName
    DetachDatabaseIfExist -server $server -databaseName ($projectName+".analytics.local")
    DetachDatabaseIfExist -server $server -databaseName ($projectName+".core.local")
    DetachDatabaseIfExist -server $server -databaseName ($projectName+".master.local")
    DetachDatabaseIfExist -server $server -databaseName ($projectName+".web.local")

    #delete folders
    $destinationFolder = $config.configuration.DestinationFolder.value
    Remove-Item -Path $destinationFolder -Force -Recurse
}
