class API {
    # member for hostname, username and password
    [string] $hostname
    [string] $username;
    [string] $password;
    [Microsoft.PowerShell.Commands.WebRequestSession] $session;
    [bool] $loggedIn = $false;
    $apiVersion = "v10.08";

    API() {}
    # constructor
    API ([string] $hostname, [string] $username, [string] $password) {
        $this.hostname = $hostname;
        $this.username = $username;
        $this.password = $password;
        $this.session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    }

    [string] subsystem_attributes_by_platform () {
        # get platform data
        $platformName = $this.platform_data_name()

        # check platform name
        if (!$platformName) {
            Throw "could not get platform name"
        }

        $attributesStr = ""
        
        switch ($platformName) {
            # Aruba 8100 won't accept poe_power attribute
            "8100" { 
                $attributesStr = "fans,temp_sensors,power_supplies,poe_power"
             }
            Default {
                $attributesStr = "fans,temp_sensors,power_supplies"
            }
        }
        return $attributesStr;
    }

    [void] buildWebSession ([string]$setCookie) {
        # set expiration date
        $date = Get-Date
        $date = $Date.AddMinutes(10)

        # parse cookies
        $cookies = $setCookie -split ','
        foreach ($cookie in $cookies) {
            $cookieKeyVal = $cookie.split(';')[0]
            $cookieKeyValArr = $cookieKeyVal.split('=', 2)
 
            # set name and value and trim whitespaces
            $name = $cookieKeyValArr[0].Trim()
            $value = $cookieKeyValArr[1].Trim()

            # skip if name or value is empty
            if (!$name -or !$value) {
                continue
            }

            # create cookie object
            $cookieObj = [System.Net.Cookie]::new($name, $value)
            
            $cookieObj.Domain = $this.hostname
            $cookieObj.Secure = $true
            $cookieObj.Path = "/"

            # set cookie property HttpOnly if name is "id", otherwise set to false
            $cookieObj.HttpOnly = ($name -eq "id")
            
            # set expiration date
            $cookieObj.Expires = $date
            
            # add cookie to session
            $this.session.Cookies.Add($cookieObj)
        }
    }

    [void] login () {
        # check if already logged in
        if ($this.loggedIn) {
            Throw "already logged in"
            return
        }

        # encode username and password
        $encUsername = [System.Web.HttpUtility]::UrlEncode($this.username)
        $encPassword = [System.Web.HttpUtility]::UrlEncode($this.password)
        
        # create login url
        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/login?username=$($encUsername)&password=$($encPassword)";
        Write-Debug "[login] POST $url"

        # perform login
        $response = Invoke-WebRequest $url -Method 'POST' -UseBasicParsing

        # throw error if request failed
        if ($response.StatusCode -ne 200) {
            Throw "got wrong status code from logout ($($response.StatusCode))"
        }
        Write-Debug "[login] Response is: $($response.StatusCode)"
        Write-Debug "[login] Login successful"

        # get session cookie
        $setCookie = $response.Headers["Set-Cookie"];
        
        Write-Debug "[login] Set-Cookie is: $setCookie"

        $this.buildWebSession($setCookie);
        $this.loggedIn = $true;
    }
    
    [void] logout () {
        # check if logged in
        if (!$this.loggedIn) {
            throw "not logged in"
            return
        }
        # create logout url
        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/logout";
        Write-Debug "[Logout] POST $url"
        

        # perform logout
        $response = Invoke-WebRequest $url -Method 'POST' -ErrorAction Stop -WebSession $this.session -UseBasicParsing

        # throw error if request failed
        if ($response.StatusCode -ne 200) {
            throw "got wrong status code from logout ($($response.StatusCode))"
        }
        Write-Debug "[Logout] Response is: $($response.StatusCode)"
        Write-Debug "[Logout] Logout successful"

        # clear session cookie
        $this.session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

        $this.loggedIn = $false;

    }

    [string] platform_data_name () {
        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/system?attributes=platform_name"
        Write-Debug "[platform_data_name] GET $url"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing
        Write-Debug "[platform_data_name] Response is: $($response.StatusCode)"

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        Write-Debug "[platform_data_name] Platform name is: $($data.platform_name)"

        return $data.platform_name
    }

    [Object] subsystem_data () {

        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $attributesStr = $this.subsystem_attributes_by_platform()
        $depth = 6
        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/system/subsystems?attributes=$($attributesStr)&depth=$($depth)"
        Write-Debug "[subsystem_data] GET $url"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing
        Write-Debug "[subsystem_data] Response is: $($response.StatusCode)"

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        return $data
    }

    [Object] firmware_data () {

        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/firmware"
        Write-Debug "[firmware_data] GET $url"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing
        Write-Debug "[firmware_data] Response is: $($response.StatusCode)"

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        return $data
    }

    [Object] config_hash ([string] $configName) {

        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/fullconfigs/hash/$($configName)"
        Write-Debug "[config_hash] GET $url"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing
        Write-Debug "[config_hash] Response is: $($response.StatusCode)"

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        return $data.sha_256_hash
    }

    [Object] interface_data () {

        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $url = "https://$($this.hostname)/rest/$($this.apiVersion)/system/interfaces?attributes=l1_state,pm_info&depth=2"
        Write-Debug "[interface_data] GET $url"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing
        Write-Debug "[interface_data] Response is: $($response.StatusCode)"

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        return $data
    }
    
}