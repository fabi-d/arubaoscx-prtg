param (
    [string] $Username,
    [string] $Password,
    [string] $IPAddress
)

Add-Type -AssemblyName System.Web

# import modules and overwrite existing ones
Import-Module $PSScriptRoot\AOS-CX\API.ps1 -Force
Import-Module $PSScriptRoot\AOS-CX\PRTGXML.ps1 -Force
Import-Module $PSScriptRoot\AOS-CX\PRTGChannel.ps1 -Force

$prtgxml = $null
$settings = $null

function getSettings() {
   $_settings = $null
   # get config with relative path

    # check if settings file exists
    if(-not (Test-Path -Path "$PSScriptRoot\AOS-CX\settings.json")) {
        # copy default settings file
        Copy-Item -Path "$PSScriptRoot\AOS-CX\settings.default.json" -Destination "$PSScriptRoot\AOS-CX\settings.json"
    }

    # read settings from file
    $_settings = Get-Content -Path "$PSScriptRoot\AOS-CX\settings.json" | ConvertFrom-Json

    # check if settings are empty
    if(-not $_settings) {
        throw "Settings file is empty"
    }
    return $_settings
}

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
    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "$ModuleDisplayName PoE drawn"
        Value = $PoePercentage
        Unit = "Percent"
        LimitMaxError = 85
    }));
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
    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "$ModuleDisplayName PSU Health"
        Value = $PowerSuppliesFailedPercentage
        Unit = "Percent"
        LimitMinError = 100
    }));
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
  
    # calculate health percentage
    $FanTraysHealthPercentage = [math]::Round((($FanTraysCount - $FanTraysFailed) / $FanTraysCount) * 100, 0)
  
    # add channel
    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "$ModuleDisplayName FanTray Health"
        Value = $FanTraysHealthPercentage
        Unit = "Percent"
        LimitMinError = 100
    }));
}
  
# add channel for a temperature sensor
function addTempSensorChannelAggregated([string] $ChannelName, [float]$Temperature, [int]$MaxTemperature = $null) {
    # add channel with limit if MaxTemperature is set
    if($MaxTemperature) {
        $prtgxml.addSensorChannel([PRTGChannel]::new(@{
            Name = $ChannelName
            Value = $Temperature
            Unit = "Temperature"
            Float = $true
            LimitMaxError = $MaxTemperature
            LimitMode = 1
        }));
    } else {
        $prtgxml.addSensorChannel([PRTGChannel]::new(@{
            Name = $ChannelName
            Value = $Temperature
            Unit = "Temperature"
            Float = $true
        }));
    }
}

function createSubsystemChannels([Object] $data) {
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

            if($settings.System.EnablePowerOverEthernetMonitoring -eq "true") {
                # check if the chassis supports PoE
                if ($PoePower -and $PoePower.available_power -gt 0) {
                    # add channel for the used PoE power in percent
                    addPoePercentageChannel $ModuleDisplayName $PoePower
                }
            }
            
            if($settings.System.EnablePowerSupplyMonitoring -eq "true") {
                # power_supplies
                $PowerSupplies = $Module.Value.power_supplies
                
                # add channel for the available power supply units in percent
                addPowerSuppliesPercentageChannel $ModuleDisplayName $PowerSupplies
            }
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

        elseif ($ModuleName -match "^management_module" -or $ModuleName -match "^line_card") {
            $TempSensors = $Module.Value.temp_sensors

            # find temp sensor with name ending with "CPU"
            $CpuTempSensor = $TempSensors.PSObject.Properties | Where-Object { $_.Value.location.ToLower() -eq "cpu" }
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
    if($settings.System.EnableFanTrayMonitoring -eq "true") {
        for ($i = 1; $i -le 10; $i++) {
            if ($GlobalFanTrays[$i].Count -gt 0) {
                addFanTrayPercentageChannel "Chassis $i" $GlobalFanTrays[$i]
            }
        }
    }

    # add temperature channels for max values if they are set
    if ($settings.System.EnableTemperatureMonitoring -eq "true") {
        if($MaxCpuTemp) {
            addTempSensorChannelAggregated "CPU Temp" $MaxCpuTemp $settings.System.CpuTemperatureThreshold
        }
        if ($MaxInletTemp) {
            addTempSensorChannelAggregated "Inlet-Air Temp" $MaxInletTemp $settings.System.AirInletTemperatureThreshold
        }
    }
}

function createTransceiverChannel([Object] $data) {
    $transceivers = 0
    $transceiverPowerErrors = 0
    $transceiverTempErrors = 0
    $transceiverBiasErrors = 0
    $transceiverVoltageErrors = 0

    foreach ($Transceiver in $data.PSObject.Properties) {
        $pmInfo = $Transceiver.Value.pm_info
        $l1_state = $Transceiver.Value.l1_state

        # skip interfaces without transceiver
        if($pmInfo.connector -eq $null -or $pmInfo.connector -eq "Absent") {
            continue
        }

        # skip interfaces without connection
        if($l1_state.l1_state_down_reason -eq "waiting_for_link" -and $settings.Transceiver.IgnoreWaitingForLinkPorts -eq "true") {
            continue
        }

        # skip interfaces that are administratively down
        if($l1_state.l1_state_down_reason -eq "admin_down" -and $settings.Transceiver.IgnoreAdminDownPorts -eq "true") {
            continue
        }

        $transceivers++

        #rx_power_high_alarm
        #rx_power_low_alarm
        #tx_power_high_alarm
        #tx_power_low_alarm

        if($pmInfo.rx_power_high_alarm -eq "On" `
        -or $pmInfo.rx_power_low_alarm -eq "On" `
        -or $pmInfo.tx_power_high_alarm -eq "On" `
        -or $pmInfo.tx_power_low_alarm -eq "On") {
            $transceiverPowerErrors++
        }

        #temperature_high_alarm
        #temperature_low_alarm

        if ($pmInfo.temperature_high_alarm -eq "On" `
        -or $pmInfo.temperature_low_alarm -eq "On") {
            $transceiverTempErrors++
        }

        #tx_bias_high_alarm
        #tx_bias_low_alarm

        if ($pmInfo.tx_bias_high_alarm -eq "On" `
        -or $pmInfo.tx_bias_low_alarm -eq "On") {
            $transceiverBiasErrors++
        }

        #vcc_high_alarm
        #vcc_low_alarm

        if ($pmInfo.vcc_high_alarm -eq "On" `
        -or $pmInfo.vcc_low_alarm -eq "On") {
            $transceiverVoltageErrors++
        }
    }

    if($transceivers -eq 0) {
        return
    }

    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Transceiver power errors"
        Value = $transceiverPowerErrors
        Unit = "Count"
        LimitMaxError = 0
    }));

    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Transceiver temperature errors"
        Value = $transceiverTempErrors
        Unit = "Count"
        LimitMaxError = 0
    }));

    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Transceiver laser bias errors"
        Value = $transceiverBiasErrors
        Unit = "Count"
        LimitMaxError = 0
    }));

    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Transceiver voltage errors"
        Value = $transceiverVoltageErrors
        Unit = "Count"
        LimitMaxError = 0
    }));
}

function createConfigSavedChannel([string] $runningConfigHash, [string] $startupConfigHash) {
    $unsavedConfig = 1 # ok

    # check if running config and startup config are equal
    if($runningConfigHash -ne $startupConfigHash) {
        $unsavedConfig = 2 # error
    }
        
    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Config saved"
        Value = $unsavedConfig
        Unit = "Custom"
        LookupName = "prtg.standardlookups.yesno.stateyesok"
    }));
}

function createVersionChannel([Object] $data) {
    # split version string of this format: "ML.10.11.1050" to major, minor and patch version and convert to integer
    $version = $data.current_version -split '\.'

    $major = [int]$version[1]
    $minor = [int]$version[2]
    $patch = [int]$version[3]

    $minMajor = [int]$settings.Version.MinimumVersion.Major
    $minMinor = [int]$settings.Version.MinimumVersion.Minor
    $minPatch = [int]$settings.Version.MinimumVersion.Patch
    
    $versionUpToDate = 1 # yes

    # compare version with minimum version in settings

    # major version is lower
    if($major -lt $minMajor) {
        $versionUpToDate = 2;  # no
    }

    # major version is equal, but minor version is lower
    elseif($major -eq $minMajor -and $minor -lt $minMinor) {
        $versionUpToDate = 2;  # no
    }

    # major and minor version are equal, but patch version is lower
    elseif($major -eq $minMajor -and $minor -eq $minMinor -and $patch -lt $minPatch) {
        $versionUpToDate = 2;  # no
    }

    $prtgxml.addSensorChannel([PRTGChannel]::new(@{
        Name = "Firmware up to date"
        Value = $versionUpToDate
        Unit = "Custom"
        LookupName = "prtg.standardlookups.yesno.stateyesok"
    }));
}

function main() {
    # get settings
    $settings = getSettings

    # set culture to en-US
    setCulture

    if($settings.Connection.TrustAllCertificates -eq "true") {
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
        
    }
    
    # create new PRTGXML object
    $prtgxml = New-Object PRTGXML
   
    # check if at least one argument is set
    if ($Username -or $Password -or $IPAddress) {
        # check if all arguments are set
        if (-not $Username -or -not $Password -or -not $IPAddress) {
            throw "Missing arguments. Please provide username, password and IP address as arguments."
        }
        $debugMode = $true
    } else {
        $Username = [System.Environment]::GetEnvironmentVariable('prtg_windowsuser')
        $Password = [System.Environment]::GetEnvironmentVariable('prtg_windowspassword')
        $IPAddress = [System.Environment]::GetEnvironmentVariable('prtg_host')
        
        # check if all environment variables are set and not empty
        if (-not $Username -or -not $Password -or -not $IPAddress) {
            Write-Host $prtgxml.getErrorXml("Missing environment variables. Please set prtg_windowsuser, prtg_windowspassword and prtg_host.")
            return
        }
    }
    
    # create new API object
    $api = New-Object API -ArgumentList $IPAddress, $Username, $Password;

    try {
        # get data from API
        $api.login();
        $subsystemData = $api.subsystem_data();
        
        # get interface data if $settings.Transceiver.EnableTransceiverMonitoring is set to true
        if ($settings.Transceiver.EnableTransceiverMonitoring -eq "true") {
            $interfaceData = $api.interface_data();
        }

        # get config hashes if $settings.Config.EnableConfigSavedMonitoring is set to true
        if ($settings.Configuration.EnableConfigurationSavedMonitoring -eq "true") {
            $runningConfigHash = $api.config_hash('running-config')
            $startupConfigHash = $api.config_hash('startup-config')
        }

        if($settings.Version.EnableVersionMonitoring -eq "true") {
            $versionData = $api.firmware_data()
            createVersionChannel $versionData
        }

        $api.logout();

        # iterate subSystemData and create channels
        createSubsystemChannels $subsystemData     

        # iterate interfaceData and create channel
        if ($settings.Transceiver.EnableTransceiverMonitoring -eq "true") {
            createTransceiverChannel $interfaceData
        }
        
        if ($settings.Configuration.EnableConfigurationSavedMonitoring -eq "true") {
            createConfigSavedChannel $runningConfigHash $startupConfigHash
        }
        
        # write XML to stdout
        Write-Host $prtgxml.getXml()
    }
    catch {
        if($debugMode) {
            throw $_
        } else {
            Write-Host $prtgxml.getErrorXml($_.Exception.Message)
        }
    } 
}

main

# remove imported modules
Remove-Module API
Remove-Module PRTGXML
Remove-Module PRTGChannel