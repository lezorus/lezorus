function ExportAlarm(){
	Connect-VIServer $serverToExportFrom -User "<username>" -Password "<password>"
	$alarmToExport = Get-AlarmDefinition $alarmToExportName
	$a = Get-View -Id $alarmToExport.Id
	$a.Info | Export-Clixml -Path $fileName -Depth ( [System.Int32]::MaxValue )
}

function ImportAlarm {

	Connect-VIServer $serverToImportTo -User "<username>" -Password "<password>"
	
	$deserializedAlarmInfo = Import-Clixml -Path $fileName
	$importedAlarmInfo = ConvertFromDeserialized( $deserializedAlarmInfo )
	$entity = Get-Folder -NoRecursion
	
	$alarmManager = Get-View -Id "AlarmManager"
	$alarmManager.CreateAlarm($entity.Id, $importedAlarmInfo)
}

# This function converts a Powershell object deserialized from xml (with Import-Clixml) to its original type (that has been previously serialized with Export-Clixml)
# The function will not work with all .NET types. It is currently tested only with the Vmware.Vim.AlarmInfo type.
function ConvertFromDeserialized {
	param(
		$deserializedObject
	)
	
	if($deserializedObject -eq $null){
		return $null
	}
		
	$deserializedTypeName = ($deserializedObject | Get-Member -Force | where { $_.Name -eq "psbase" } ).TypeName;
	
	if($deserializedTypeName.StartsWith("Deserialized.")) {
		$originalTypeName = $deserializedTypeName.Replace("Deserialized.", "")
		$result = New-Object -TypeName $originalTypeName
		$resultType = $result.GetType()
		
		if($resultType.IsEnum){
			$result = [Enum]::Parse($resultType, $deserializedObject, $true)
			return $result
		}
		
		$deserializedObject | Get-Member | % { 
			if($_.MemberType -eq "Property") {
				$resultProperty = $resultType.GetProperty($_.Name)
				if($resultProperty.CanWrite){
					$propertyValue = ( Invoke-Expression ('$deserializedObject.' + $_.Name) | % { ConvertFromDeserialized( $_ ) } ) 
					if($propertyValue -and $resultProperty.PropertyType.IsArray ) {
						if($propertyValue.GetType().IsArray){
							# convert the elements
							$elementTypeName = $resultProperty.PropertyType.AssemblyQualifiedName.Replace("[]", "")
							$elementType = [System.Type]::GetType($elementTypeName)
							$array = [System.Array]::CreateInstance($elementType, $propertyValue.Count)
							for($i = 0; $i -lt $array.Length; $i++){
								$array[$i] = $propertyValue[$i]
							}
							$propertyValue = $array
						} else {
							$elementTypeName = $resultProperty.PropertyType.AssemblyQualifiedName.Replace("[]", "")
							$elementType = [System.Type]::GetType($elementTypeName)
							$array = [System.Array]::CreateInstance($elementType, 1)
							$array[0] = $propertyValue
							$propertyValue = $array
						}
					}
					$resultProperty.SetValue($result, $propertyValue, $null)
				}
			}
		} 
	} else {
		$result = $deserializedObject
	}
	
	return $result	
}

# Example of exporting and importing an alarm - uncomment the desired action
# This script allows you to export an alarm from a vCenter server and import it to another one, whus maintaining a "mirror" of the original alarm
$fileName = "C:\custom_alarmdef.xml"
$serverToExportFrom = "<server_to_export_name>"
$serverToImportTo = "<server_to_export_name>"
$alarmToExportName = "<alarm_name>"
ExportAlarm
#ImportAlarm
