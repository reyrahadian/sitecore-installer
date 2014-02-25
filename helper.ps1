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