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
  [void] addSensorChannel([string] $Name, [string] $Value, [string] $Unit, [int] $Float) {
    $prtgResult = $this.xml.CreateElement("result")
    $this.root.AppendChild($prtgResult) | Out-Null
  
    $prtgChannel = $this.xml.CreateElement("channel")
    $prtgChannel.InnerText = $Name
    $prtgResult.AppendChild($prtgChannel) | Out-Null
  
    $prtgValue = $this.xml.CreateElement("value")
    $prtgValue.InnerText = $Value
    $prtgResult.AppendChild($prtgValue) | Out-Null
  
    $prtgUnit = $this.xml.CreateElement("unit")
    $prtgUnit.InnerText = $Unit
    $prtgResult.AppendChild($prtgUnit) | Out-Null
  
    $prtgFloat = $this.xml.CreateElement("float")
    $prtgFloat.InnerText = $Float
    $prtgResult.AppendChild($prtgFloat) | Out-Null
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