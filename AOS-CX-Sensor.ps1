Add-Type -AssemblyName System.Web

# import modules and overwrite existing ones
Import-Module $PSScriptRoot\AOS-CX\API.ps1 -Force
Import-Module $PSScriptRoot\AOS-CX\PRTGXML.ps1 -Force

$prtgxml = $null

add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
            return true;
        }
 }
"@

# disable certificate check
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# set culture to en-US to avoid problems with decimal point in XML
function setCulture() {
    # set decimal point for serialization in XML
    $culture = [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    $culture.NumberFormat.NumberDecimalSeparator = "."
    $culture.NumberFormat.NumberGroupSeparator = ","
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
}

# replace name of modules for better readability in PRTG
function mapModuleName([string] $ModuleName) {
    $ModuleName = $ModuleName -replace "chassis,", "Chassis "
    $ModuleName = $ModuleName -replace "line_card,", "Linecard "
    $ModuleName = $ModuleName -replace "management_module,", "MgmtModule "
    $ModuleName = $ModuleName -replace "fan_tray,", "FanTray "
  
    return $ModuleName
}

# add channel for the used PoE power in percent of a single chassis (switch) 
function addPoePercentageChannel([string] $ModuleDisplayName, [Object] $PoePower) {
    $PoeAvailable = $PoePower.available_power
    $PoeConsumed = $PoePower.drawn_power
  
    # calculate percentage
    $PoePercentage = [math]::Round(($PoeConsumed / $PoeAvailable) * 100, 0)
  
    # add channel
    $prtgxml.addSensorChannel("$ModuleDisplayName PoE drawn", $PoePercentage, "Percent", 0)
}
  
# add channel for the available power supply units in percent of a single chassis (switch)
function addPowerSuppliesPercentageChannel([string] $ModuleDisplayName, [Object] $PowerSupplies) {
    $PowerSuppliesCount = 0
    $PowerSuppliesFailed = 0
  
    foreach ($PowerSupply in $PowerSupplies.PSObject.Properties) {
        $PowerSuppliesCount++
        if ($PowerSupply.Value.status -ne "ok") {
            $PowerSuppliesFailed++
        }
    }
  
    # return if no power supplies found
    if ($PowerSuppliesCount -eq 0) {
        return
    }
  
    # calculate failed percentage
    $PowerSuppliesFailedPercentage = [math]::Round((($PowerSuppliesCount - $PowerSuppliesFailed) / $PowerSuppliesCount) * 100, 0)
  
    # add channel
    $prtgxml.addSensorChannel("$ModuleDisplayName PSU Health", $PowerSuppliesFailedPercentage, "Percent", 0)
}
  
# add channel for the available fan trays in percent of a single chassis (switch)
function addFanTrayPercentageChannel([string] $ModuleDisplayName, [Object[]] $FanTrays) {
    $FanTraysCount = 0
    $FanTraysFailed = 0
  
    foreach ($FanTray in $FanTrays) {
        $FanTraysCount++
        if ($FanTray.Value.status -ne "ok") {
            $FanTraysFailed++
        }
    }
  
    # return if no fan trays found
    if ($FanTraysCount -eq 0) {
        return
    }
  
    # calculate failed percentage
    $FanTraysFailedPercentage = [math]::Round((($FanTraysCount - $FanTraysFailed) / $FanTraysCount) * 100, 0)
  
    # add channel
    $prtgxml.addSensorChannel("$ModuleDisplayName FanTray Health", $FanTraysFailedPercentage, "Percent", 0)
}
  
# add channel for a temperature sensor
function addTempSensorChannelAggregated([string] $ChannelName, [float]$Temperature) {
    $prtgxml.addSensorChannel($ChannelName, $Temperature.ToString("0.0"), "Temperature", 1)
}

function createChannels([Object] $data) {
    # store fan trays per chassis in array
    $GlobalFanTrays = @()

    # store max temps of stack (multiple chassis)
    $MaxCpuTemp = $null
    $MaxInletTemp = $null

    # create inner array for each possible chassis
    for ($i = 1; $i -le 11; $i++) {
        $GlobalFanTrays += @($null)
    }

    foreach ($Module in $data.PSObject.Properties) {
        $ModuleName = $Module.Name
        $ModuleDisplayName = mapModuleName $ModuleName

        if ($ModuleName -match "^chassis") {
            $PoePower = $Module.Value.poe_power

            # check if the chassis supports PoE
            if ($PoePower -and $PoePower.available_power -gt 0) {
                # add channel for the used PoE power in percent
                addPoePercentageChannel $ModuleDisplayName $PoePower
            }
    
            # power_supplies
            $PowerSupplies = $Module.Value.power_supplies
            
            # add channel for the available power supply units in percent
            addPowerSuppliesPercentageChannel $ModuleDisplayName $PowerSupplies

        }
  
        elseif ($ModuleName -match "^fan_tray") {
            $ModuleFanTrays = $Module.Value.fans

            # get chassis id from fan tray name ("Tray-1/1/1" is chassis "1", "Tray-2/1/1" is chassis "2" and so on)
            $ChassisId = $ModuleName -replace "fan_tray,(\d+)/.*", '$1'

            # if chassis id can be converted to a number and is greater than 0
            if ([int]::TryParse($ChassisId, [ref]$ChassisId) -and $ChassisId -gt 0 -and $ChassisId -le 10) {
                # add fan to array
                $GlobalFanTrays[$ChassisId] += $ModuleFanTrays.PSObject.Properties
            }
            else {
                Write-Error "Could not parse chassis id from module name $($ModuleName)"
                continue
            }
        }
  
        elseif ($ModuleName -match "^line_card") {
            # currently not needed
        }

        elseif ($ModuleName -match "^management_module") {
            $TempSensors = $Module.Value.temp_sensors

            # find temp sensor with name ending with "CPU"
            $CpuTempSensor = $TempSensors.PSObject.Properties | Where-Object { $_.Value.name -match "CPU$" }
            if ($CpuTempSensor) {
                # convert millidegree to degree
                $Temperature = [math]::Round($CpuTempSensor.Value.temperature / 1000, 1)

                # store max temp of stack
                if ($null -eq $MaxCpuTemp -or $Temperature -gt $MaxCpuTemp) {
                    $MaxCpuTemp = $Temperature
                }
            }

            # find temp sensor with name ending with "Inlet"
            $InletTempSensor = $TempSensors.PSObject.Properties | Where-Object { $_.Value.name -match "Inlet-Air$" }
            if ($InletTempSensor) {
                # convert millidegree to degree
                $Temperature = [math]::Round($InletTempSensor.Value.temperature / 1000, 1)

                # store max temp of stack
                if ($null -eq $MaxInletTemp -or $Temperature -gt $MaxInletTemp) {
                    $MaxInletTemp = $Temperature
                }
            }
        }
        else {
            Write-Error "Unknown module type: $ModuleName"
        }
    }

    # iterate over $GlobalFanTrays and call addFanTrayPercentageChannel for each chassis if fan trays are found
    for ($i = 1; $i -le 10; $i++) {
        if ($GlobalFanTrays[$i].Count -gt 0) {
            addFanTrayPercentageChannel "Chassis $i" $GlobalFanTrays[$i]
        }
    }

    # add temperature channels for max values if they are set
    if ($MaxCpuTemp) {
        addTempSensorChannelAggregated "CPU Temp" $MaxCpuTemp
    }
    if ($MaxInletTemp) {
        addTempSensorChannelAggregated "Inlet-Air Temp" $MaxInletTemp
    }
}

function main() {
    setCulture

    # get environment variables from PRTG
    $Username = [System.Environment]::GetEnvironmentVariable('prtg_windowsuser')
    $Password = [System.Environment]::GetEnvironmentVariable('prtg_windowspassword')
    $IPAddress = [System.Environment]::GetEnvironmentVariable('prtg_host')
  
    # create new API object
    $api = New-Object API -ArgumentList $IPAddress, $Username, $Password;
    
    # create new PRTGXML object
    $prtgxml = New-Object PRTGXML

    try {
        # get data from API
        $api.login();
        $data = $api.subsystem_data();
        $api.logout();

        # iterate data and create channels
        createChannels $data
    
        # write XML to stdout
        Write-Host $prtgxml.getXml()
    }
    catch {
        Write-Host $prtgxml.getErrorXml($_.Exception.Message)
    }
}

main

# remove imported modules
Remove-Module API
Remove-Module PRTGXML