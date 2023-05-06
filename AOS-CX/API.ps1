class API {
    # member for hostname, username and password
    [string] $hostname
    [string] $username;
    [string] $password;
    [Microsoft.PowerShell.Commands.WebRequestSession] $session;
    [bool] $loggedIn = $false;

    API() {}
    # constructor
    API ([string] $hostname, [string] $username, [string] $password) {
        $this.hostname = $hostname;
        $this.username = $username;
        $this.password = $password;
        $this.session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
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
        $url = "https://$($this.hostname)/rest/v10.08/login?username=$($encUsername)&password=$($encPassword)";

        # perform login
        $response = Invoke-WebRequest $url -Method 'POST' -UseBasicParsing

        # throw error if request failed
        if ($response.StatusCode -ne 200) {
            Throw "got wrong status code from logout ($($response.StatusCode))"
        }

        # get session cookie
        $setCookie = $response.Headers["Set-Cookie"];

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
        $url = "https://$($this.hostname)/rest/v10.08/logout";
        

        # perform logout
        $response = Invoke-WebRequest $url -Method 'POST' -ErrorAction Stop -WebSession $this.session -UseBasicParsing

        # throw error if request failed
        if ($response.StatusCode -ne 200) {
            throw "got wrong status code from logout ($($response.StatusCode))"
        }

        # clear session cookie
        $this.session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

        $this.loggedIn = $false;

    }

    [Object] subsystem_data () {
        # check if logged in
        if (!$this.loggedIn) {
            Throw "not logged in"
        }

        $depth = 6
        $attributesStr = "fans,temp_sensors,poe_power,power_supplies"
        $url = "https://$($this.hostname)/rest/v10.08/system/subsystems?attributes=$($attributesStr)&depth=$($depth)"

        # perform request
        $response = Invoke-WebRequest $url -Method 'GET' -WebSession $this.session -UseBasicParsing

        $data = $response.Content | ConvertFrom-Json
        $data = $data[0]

        return $data
    }
    
}