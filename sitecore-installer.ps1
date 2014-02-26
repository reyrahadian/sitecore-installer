#load helper file
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$currentDirectory = [IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$helperFile = [IO.Path]::Combine($currentDirectory, 'helper.ps1')
. $helperFile

$carbonHelperFile = [IO.Path]::Combine($currentDirectory, 'Carbon-1.6.0\Carbon\Import-Carbon.ps1')
. $carbonHelperFile

#read from config file
$config = ReadConfigFile $currentDirectory
$sourceFolder = $config.configuration.SourceFolder.value
$destinationFolder = $config.configuration.DestinationFolder.value
$cmsZipFileName = $config.configuration.Sitecore.CmsZipFile.value
$dmsZipFileName = $config.configuration.Sitecore.DmsZipFile.value

#remove all previous setup -- for debug only
TearDownExistingInstallation $config

#folder path check
$cmsSourceZipFilePath = $($sourceFolder)+$($cmsZipFileName)
$dmsSourceZipFilePath = $($sourceFolder)+$($dmsZipFileName)
ThrowErrorIfPathIsInvalid($cmsSourceZipFilePath)
ThrowErrorIfPathIsInvalid($dmsSourceZipFilePath)
EnsureFolderExist($destinationFolder)

#db instance check
$sqlServerInstanceName = $config.configuration.Database.TargetInstance.value
ThrowIfDbInstanceDoesNotExist($sqlServerInstanceName)

#copy zip files to target folder
Copy-Item $cmsSourceZipFilePath $destinationFolder -force
Copy-Item $dmsSourceZipFilePath $destinationFolder -force

#extract zip file
$cmsDestinationZipFilePath = $($destinationFolder)+$($cmsZipFileName)
$dmsDestinationZipFilePath = $($destinationFolder)+$($dmsZipFileName)
$websiteFolderPath = $destinationFolder+"website\"
$databaseFolderPath = $destinationFolder+"databases\"

ExtractCmsZipFile -file $cmsDestinationZipFilePath -destination $destinationFolder
ExtractDmsZipFile -file $dmsDestinationZipFilePath -websiteFolderPath $websiteFolderPath -databaseFolderPath $databaseFolderPath

#remove zip files
Remove-Item $dmsDestinationZipFilePath
Remove-Item $cmsDestinationZipFilePath

#copy sitecore license file
$sitecoreLicenseFilePath = $config.configuration.Sitecore.LicenseKeyFile.value
ThrowErrorIfPathIsInvalid($sitecoreLicenseFilePath)
$dataFolderPath = $destinationFolder+"data"
ThrowErrorIfPathIsInvalid($dataFolderPath)
Copy-Item $sitecoreLicenseFilePath $dataFolderPath -Force

#update Sitecore datafolder.config
$datafolderConfigPath = $websiteFolderPath+"\app_config\include\datafolder.config.example"
ThrowErrorIfPathIsInvalid($datafolderConfigPath)
$dataFolderConfig = [xml](cat $datafolderConfigPath)
$dataFolderConfig.configuration.sitecore.'sc.variable'.attribute.InnerText = $dataFolderPath
$dataFolderConfig.Save($datafolderConfigPath)
Rename-Item -NewName "DataFolder.config" -Path $datafolderConfigPath


#Register site in IIS
$hostName = $config.configuration.IIS.HostName.value
$webApp = Get-WebApplication $hostName
if($webApp -eq $null){
    New-WebAppPool $hostName -Force
}
New-Website -Name $hostName -Port 80 -HostHeader $hostName -ApplicationPool $hostName -PhysicalPath $websiteFolderPath -Force

#Update host file
Set-HostsEntry -IPAddress 127.0.0.1 -HostName $hostName

#Modify db connection string
$connectionStringFilePath = $websiteFolderPath+"\app_config\connectionstrings.config"
ThrowErrorIfPathIsInvalid($connectionStringFilePath)
$connectionStringConfig = [xml](cat $connectionStringFilePath)
$connectionStringConfig.connectionStrings.InnerXml = $config.configuration.connectionStrings.InnerXml
$connectionStringConfig.Save($connectionStringFilePath)

#Create db user if necessary
$dbServer = GetDbServerInstance $sqlServerInstanceName
CreateDbUserIfNotExist -server $dbServer -username $config.configuration.Database.User.username -password $config.configuration.Database.User.password

#Attach database files
$projectName = $config.configuration.Project.value
AttachDatabaseFile -server $dbServer -databaseName ($projectName+".analytics.local") -databaseFilePath ($databaseFolderPath+"sitecore.analytics")
AttachDatabaseFile -server $dbServer -databaseName ($projectName+".core.local") -databaseFilePath ($databaseFolderPath+"sitecore.core")
AttachDatabaseFile -server $dbServer -databaseName ($projectName+".master.local") -databaseFilePath ($databaseFolderPath+"sitecore.master")
AttachDatabaseFile -server $dbServer -databaseName ($projectName+".web.local") -databaseFilePath ($databaseFolderPath+"sitecore.web")

#Sitecore hardening

#Start website
Start-Website -Name $hostName

#Open site in browser
Start-Process -FilePath "http://"$hostName