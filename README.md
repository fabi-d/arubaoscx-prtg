# ArubaOS-CX PRTG Script Sensor

This repository contains a Powershell script sensor for Paessler PRTG which allows you to monitor the health of Aruba switches with ArubaOS-CX operating system (6000 series, 8000 series).

## Features
The sensor allows you to monitor the following parameters of individual switches and VSF stacks as well as members of VSX stacks
- Current usage of PoE budget per Switch in percent
- State of power supplies in percent
- State of fan trays in percent
- highest currently measured CPU temperature (of all chassis in the stack)
- highest currently measured intake temperature (of all chassis in the stack)

![Preview of the sensor channels](/Info/Screenshot-PRTG-Result.png)

## Requirements
The script uses the REST API 10.08 of the ArubaOS-CX switches. It is therefore necessary that the switches to be monitored have at least version 10.08.

## Installation
To install the sensor, copy the files (AOS-CX folder and AOS-CX-Sensor.ps1) to the `PRTG Network Monitor\Custom Sensors\EXEXML` folder on your PRTG core server and remote probes that are supposed to use the script sensor.

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
user monitoring group operators password plaintext <securepassword>
```

### PRTG login data
The API credentials must be stored in the Windows credentials of the device (or inherited to the device via the group).

![Preview of the sensor settings](/Info/Screenshot-PRTG-Login.png)

### PRTG sensor
In the PRTG sensor settings, the "Environment" setting must be set to "Set placeholders as environment values" so that the switch hostname/IP address and windows login data is passed to the script as environment variables.

![Preview of the sensor settings](/Info/Screenshot-PRTG-Config.png)

## Note for stacks
For a VSF stack only one sensor needs to be added, VSX stacks need to be monitored individually (one sensor per device).
