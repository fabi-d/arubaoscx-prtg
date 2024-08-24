# ArubaOS-CX PRTG Script Sensor

This repository contains a Powershell script sensor for Paessler PRTG which allows you to monitor the health of Aruba switches with ArubaOS-CX operating system (6000 series, 8000 series).

## Features
The sensor allows you to monitor the following parameters of individual switches and VSF stacks as well as members of VSX stacks
- Temperatures
    - highest currently measured CPU temperature (of all chassis in the VSF stack)
    - highest currently measured intake temperature (of all chassis in the stack)
- Tranceivers
    - Transceiver laser errors
    - Transceiver power errors
    - Transceiver temperature errors
    - Transceiver voltage errors
- Power supplies
    - Current usage of PoE budget per Switch in percent
    - State of available power supplies (in percent)
- State of available fan trays (in percent)
- Firmware version baseline check (disabled by default, can be configures in settings file `AOS-CX\settings.json`)
- Unsaved configuration changes (comparison of running config and saved config)
- All sensor channels can be activated/deactivated via the configuration file `AOS-CX\settings.json`

![Preview of the sensor channels](/Info/Screenshot-PRTG-Result.png)

## Tested Switches
The sensor has already been successfully tested on the following devices:
- Aruba 6000
- Aruba 6100
- Aruba 6200F/6200M
- Aruba 6300M
- Aruba 8325
    - Switch does not have a CPU temperature sensor, but only a temperature sensor in a line card that has “CPU” specified as the location. This is used

*Please let me know if you have successfully/unsuccessfully tested another Switch model.*

## Requirements
The script uses the REST API 10.08 of the ArubaOS-CX switches. It is therefore necessary that the switches to be monitored have at least version 10.08.

## Installation
### Copy files to PRTG servers
To install the sensor, copy the files (AOS-CX folder and AOS-CX-Sensor.ps1) to the `PRTG Network Monitor\Custom Sensors\EXEXML` folder on your PRTG core server and remote probes that are supposed to use the script sensor.


### Powershell Execution Policy
Since PRTG uses the **x86 powershell**, the script execution policy must be adjusted in this x86 powershell so that the script sensor can be executed.
```powershell
# Windows PowerShell (x86) on PRTG servers
Set-ExecutionPolicy Unrestricted
```
![Preview of the sensor settings](/Info/Screenshot-Powershell-x86.png)

### Switch configuration
The Windows login data for the device set in PRTG is passed to the script as environment values.

In order to use the REST API of a ArubaOS-CX switch, the web server must be enabled in the VRF, which is used to access the switch from PRTG. 
Additionally, a password must be set for the admin user to enable the API feature.

```diff
# access via default vrf
https-server vrf default

# access via OOB management port
https-server vrf mgmt 

# access-mode can be set to readonly
https-server rest access-mode read-only

# (optional, but recommended) add a separate monitoring user 
user monitoring group administrators password plaintext <securepassword>
```

### PRTG login data
The API credentials must be stored in the Windows credentials of the device (or inherited to the device via the group).

![Preview of the sensor settings](/Info/Screenshot-PRTG-Login.png)

### PRTG sensor
In the PRTG sensor settings, the "Environment" setting must be set to "Set placeholders as environment values" so that the switch hostname/IP address and windows login data is passed to the script as environment variables.

![Preview of the sensor settings](/Info/Screenshot-PRTG-Config.png)

## Note for stacks
For a VSF stack only one sensor needs to be added, VSX stacks need to be monitored individually (one sensor per device).

## Settings 
All sensor channels and settings can be configured in the `AOS-CX\settings.json` settings file (generated when the sensor is first executed, if not already present).

```jsonc
{
    "Connection": {
        "TrustAllCertificates":  "true"                 // ignore certificate errors 
    },
    "System": {
        "EnableFanTrayMonitoring": "true",              // enable fan tray channels
        "EnablePowerSupplyMonitoring": "true",          // enable power supply channels
        "EnableTemperatureMonitoring": "true",          // enable temperature channels
        "EnablePowerOverEthernetMonitoring": "true",    // enable PoE channels
        "CpuTemperatureThreshold": "65",                // cpu temperature threshold for error
        "AirInletTemperatureThreshold": "45"            // inlet temperature threshold for error
    },
    "Transceiver": {
        "EnableTransceiverMonitoring": "true",          // enable tranceiver channels
        "IgnoreWaitingForLinkPorts": "true",            // do not generate errors for ports that are in waiting for link state
        "IgnoreAdminDownPorts": "true"                  // do not generate errors for ports that are admin shutdown 
    },
    "Version": {
        "EnableVersionMonitoring": "false",             // enable firmware version monitoring (disabled by default)
        "MinimumVersion": {                             // Minimum version for which no error is generated (here 10.11.0)
            "Major": "10",
            "Minor": "11",
            "Patch": "0"
        }
    },
    "Configuration": {
        "EnableConfigurationSavedMonitoring": "true"    // generate error, if the running config and the saved config are different
    }
}
```

## Troubleshooting
To test the sensor, the script can be executed on the PRTG server in debug mode.
In order for the debug messages to be displayed, `$DebugPreference = “Continue”` must be set.

The script can then be called with the parameters `-Username`, `-Password` and `-IPAddress`.

The output should look like this:
```Powershell
# Debug mode
PS E:\PRTG Network Monitor\Custom Sensors\EXEXML> $DebugPreference = "Continue"

# Execute script with parameters
PS E:\PRTG Network Monitor\Custom Sensors\EXEXML> .\AOS-CX-Sensor.ps1 -Username "api" -Password "<XXXXXX>" -IPAddress "192.168.180.50"

DEBUG: [login] POST https://192.168.180.50/rest/v10.08/login?username=api&password=<XXXXXX>
DEBUG: [login] Response is: 200
DEBUG: [login] Login successful
DEBUG: [login] Set-Cookie is: id=XXXXXXXXXXXXXX==; Path=/; HttpOnly; Secure; SameSite=Lax
DEBUG: [platform_data_name] GET https://192.168.180.50/rest/v10.08/system?attributes=platform_name
DEBUG: [platform_data_name] Response is: 200
DEBUG: [platform_data_name] Platform name is: 6200
DEBUG: [subsystem_data] GET https://192.168.180.50/rest/v10.08/system/subsystems?attributes=fans,temp_sensors,power_supplies&depth=6
DEBUG: [subsystem_data] Response is: 200
DEBUG: [interface_data] GET https://192.168.180.50/rest/v10.08/system/interfaces?attributes=l1_state,pm_info&depth=2
DEBUG: [interface_data] Response is: 200
DEBUG: [config_hash] GET https://192.168.180.50/rest/v10.08/fullconfigs/hash/running-config
DEBUG: [config_hash] Response is: 200
DEBUG: [config_hash] GET https://192.168.180.50/rest/v10.08/fullconfigs/hash/startup-config
DEBUG: [config_hash] Response is: 200
DEBUG: [Logout] POST https://192.168.180.50/rest/v10.08/logout
DEBUG: [Logout] Response is: 200
DEBUG: [Logout] Logout successful
<prtg>
  <result>
    <channel>Chassis 1 PSU Health</channel>
    <value>100</value>
    <unit>Percent</unit>
    <limitminerror>100</limitminerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>CPU Temp</channel>
    <value>46.1</value>
    <unit>Temperature</unit>
    <float>1</float>
    <limitmaxerror>65</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Inlet-Air Temp</channel>
    <value>21.2</value>
    <unit>Temperature</unit>
    <float>1</float>
    <limitmaxerror>45</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Transceiver power errors</channel>
    <value>0</value>
    <unit>Count</unit>
    <limitmaxerror>0</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Transceiver temperature errors</channel>
    <value>0</value>
    <unit>Count</unit>
    <limitmaxerror>0</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Transceiver laser bias errors</channel>
    <value>0</value>
    <unit>Count</unit>
    <limitmaxerror>0</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Transceiver voltage errors</channel>
    <value>0</value>
    <unit>Count</unit>
    <limitmaxerror>0</limitmaxerror>
    <limitmode>1</limitmode>
  </result>
  <result>
    <channel>Config saved</channel>
    <value>1</value>
    <unit>Custom</unit>
    <valuelookup>prtg.standardlookups.yesno.stateyesok</valuelookup>
  </result>
</prtg>
```