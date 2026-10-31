$ErrorActionPreference = 'Stop'
$inputStream = [Console]::OpenStandardInput()
$outputStream = [Console]::OpenStandardOutput()
$buffer = New-Object byte[] 4096
while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $outputStream.Write($buffer, 0, $count)
    $outputStream.Flush()
}
[Console]::Error.WriteLine('EOF')
