class PRTGXML {
  [System.Xml.XmlDocument] $xml
  [System.Xml.XmlElement] $root

  # constructor
  PRTGXML() {
    $this.xml = New-Object System.Xml.XmlDocument

    $this.root = $this.xml.CreateElement("prtg")
    $this.xml.AppendChild($this.root) | Out-Null
  }

  # add sensor channel
  [void] addSensorChannel([Object] $Sensor) {
    $prtgResult = $this.xml.CreateElement("result")
    $this.root.AppendChild($prtgResult) | Out-Null
  
    $prtgChannel = $this.xml.CreateElement("channel")
    $prtgChannel.InnerText = $Sensor.Name
    $prtgResult.AppendChild($prtgChannel) | Out-Null
  
    $prtgValue = $this.xml.CreateElement("value")
    $prtgValue.InnerText = $Sensor.Value
    $prtgResult.AppendChild($prtgValue) | Out-Null
  
    $prtgUnit = $this.xml.CreateElement("unit")
    $prtgUnit.InnerText = $Sensor.Unit
    $prtgResult.AppendChild($prtgUnit) | Out-Null

    if($Sensor.Float -eq $true) {
      $prtgFloat = $this.xml.CreateElement("float")
      $prtgFloat.InnerText = 1
      $prtgResult.AppendChild($prtgFloat) | Out-Null
    }

    if($null -ne $Sensor.LookupName) {
      $prtgLookupName = $this.xml.CreateElement("valuelookup")
      $prtgLookupName.InnerText = $Sensor.LookupName
      $prtgResult.AppendChild($prtgLookupName) | Out-Null
    }

    if($Sensor.LimitMaxError -ne $null) {
      $prtgLimitMaxError = $this.xml.CreateElement("limitmaxerror")
      $prtgLimitMaxError.InnerText = $Sensor.LimitMaxError
      $prtgResult.AppendChild($prtgLimitMaxError) | Out-Null

    }

    if($Sensor.LimitMinError -ne $null) {
      $prtgLimitMinError = $this.xml.CreateElement("limitminerror")
      $prtgLimitMinError.InnerText = $Sensor.LimitMinError
      $prtgResult.AppendChild($prtgLimitMinError) | Out-Null
    }

    if($Sensor.LimitMaxError -ne $null -or $Sensor.LimitMinError -ne $null) {
      $prtgLimitMode = $this.xml.CreateElement("limitmode")
      $prtgLimitMode.InnerText = 1
      $prtgResult.AppendChild($prtgLimitMode) | Out-Null
    }
  

  }

  # write XML
  [string] getXml() {
    # create XML writer
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;

    # set formatting
    $XmlWriter.Formatting = "indented";

    # write XML
    $this.xml.WriteTo($XmlWriter);
    
    # flush and return XML
    $XmlWriter.Flush();
    $StringWriter.Flush();
    return $StringWriter.ToString();
  }

  # return error XML for PRTG
  [string] getErrorXml([string] $ErrorMessage) {
    return "<prtg><error>1</error><text>$ErrorMessage</text></prtg>"
  }
}