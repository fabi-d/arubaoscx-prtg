class PRTGChannel {
    [string] $Name
    [string] $Value
    [string] $Unit
    [bool] $Float = $false
    [string] $LookupName
    [nullable[int]] $LimitMaxError
    [nullable[int]] $LimitMinError

    PRTGChannel ([hashtable] $Info) {
        switch ($Info.Keys) {
            "Name" {
                $this.Name = $Info["Name"]
            }
            "Value" {
                $this.Value = $Info["Value"].ToString()
            }
            "Unit" {
                $this.Unit = $Info["Unit"]
            }
            "Float" {
                $this.Float = $Info["Float"]
            }
            "LookupName" {
                $this.LookupName = $Info["LookupName"]
            }
            "LimitMaxError" {
                $this.LimitMaxError = $Info["LimitMaxError"]
            }
            "LimitMinError" {
                $this.LimitMinError = $Info["LimitMinError"]
            }  
        }
    }
}
