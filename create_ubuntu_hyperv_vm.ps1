# ADK Download - https://www.microsoft.com/en-us/download/confirmation.aspx?id=39982
# You only need to install the deployment tools
$oscdimgPath = "C:\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

# Download qemu-img from here: http://www.cloudbase.it/qemu-img-windows/
$qemuImgPath = "C:\bin\qemu-img.exe"

# Update this to the release of Ubuntu that you want
# https://cloud-images.ubuntu.com/xenial/current/
# https://cloud-images.ubuntu.com/bionic/current/
# https://cloud-images.ubuntu.com/cosmic/current/
# https://cloud-images.ubuntu.com/disco/current/
$ubuntuPath = "https://cloud-images.ubuntu.com/disco/current/disco-server-cloudimg-amd64.img"

$GuestOSID = "iid-123456"
# password for the ubuntu user
$GuestAdminPassword = "Passw0rd"

$VMName = "Ubuntu Test"
$virtualSwitchName = "External"

$vmPath = "F:\Hyper-V\VHDs\cosmic\VM"
$imageCachePath = "F:\Hyper-V\VHDs\cosmic"
$vhdx = "$($vmPath)\test.vhdx"
$metaDataIso = "$($vmPath)\metadata.iso"

$metadata = @"
instance-id: $($GuestOSID)
"@

$userdata = @"
#cloud-config
password: $($GuestAdminPassword)
chpasswd: { expire: False }
# Allow password authentication
ssh_pwauth: True

runcmd:
 - [ useradd, -m, -p, "", ben ]
 # Allow root login - must set password first
 - sed -i -e 's/.PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
 # restart ssh service
 - [service, ssh, restart ]
 # disable irqbalance service
 - [systemctl, disable, irqbalance ]
 # download setup scripts for automation preparation
 - [ wget, "https://github.com/LIS/lis-test/raw/master/WS2012R2/lisa/Infrastructure/aio.sh", -O, /tmp/aio.sh ]
 # preparation to still be able to use old ifupdown after manually remove cloud-init and cleanup
 - echo 'auto eth0' >> /etc/network/interfaces
 - echo 'iface eth0 inet dhcp' >> /etc/network/interfaces
packages:
 - linux-tools-generic
 - linux-cloud-tools-generic
 - dos2unix
"@

# Helper function for no error file cleanup
Function cleanupFile ([string]$file) {
    if (test-path $file) {
        Remove-Item $file
    }
}

# Check Paths
if (!(test-path $vmPath)) {
    mkdir $vmPath
}
if (!(test-path $imageCachePath)) {
    mkdir $imageCachePath
}

# Delete the VM if it exists
if ((Get-VM | Where-Object name -eq $VMName).Count -gt 0) {
    Stop-VM $VMName -TurnOff -Confirm:$false -Passthru | Remove-VM -Force
}

cleanupFile $vhdx
cleanupFile $metaDataIso

# Make temp location
$tempPath = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
mkdir -Path $tempPath
mkdir -Path "$($tempPath)\Bits"

# Download the cloud image
(New-Object System.Net.WebClient).DownloadFile("$ubuntuPath","$($imageCachePath)\disco-server-cloudimg-amd64.img")

# Output meta and user data to files
Set-Content "$($tempPath)\Bits\meta-data" ([byte[]][char[]] "$metadata") -Encoding Byte
Set-Content "$($tempPath)\Bits\user-data" ([byte[]][char[]] "$userdata") -Encoding Byte

# Convert cloud image to VHDx
& $qemuImgPath convert -f qcow2 "$($imageCachePath)\disco-server-cloudimg-amd64.img" -O vhdx -o subformat=dynamic $vhdx
Resize-VHD -Path $vhdx -SizeBytes 64GB
Convert-VHD -Path $vhdx -DestinationPath "$($vmPath)\test_tmp.vhdx" -DeleteSource -BlockSizeBytes 1MB -VHDType Dynamic
Move-Item "$($vmPath)\test_tmp.vhdx" $vhdx

# Create meta data ISO image
& $oscdimgPath "$($tempPath)\Bits" $metaDataIso -j2 -lcidata

# Clean-up temp directory
Remove-Item -Path $tempPath -Recurse -Force

# Create new virtual machine and start it
New-VM $VMName -MemoryStartupBytes 2048MB -VHDPath $vhdx -Generation 1 `
               -SwitchName $virtualSwitchName -Path $vmPath | Out-Null
Set-VM -Name $VMName -ProcessorCount 4
Set-VMDvdDrive -VMName $VMName -Path $metaDataIso
Start-VM $VMName

# Open-up VMConnect
Invoke-Expression "vmconnect.exe localhost `"$VMName`""
