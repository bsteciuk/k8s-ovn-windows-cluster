
param (
    [Parameter(Mandatory=$true)][string]$networkInterfaceAlias,
    [Parameter(Mandatory=$false)][switch]$vagrant = $false,
    [Parameter(Mandatory=$false)][string]$masterIp = "172.20.2.30",
    [Parameter(Mandatory=$false)][string]$clusterSubnet = "192.168.0.0/16",
    [Parameter(Mandatory=$false)][string]$serviceClusterIpRange = "172.16.1.0/24"
)

#Only run this if vagrant
if ($vagrant) {
    Set-Location -Path "C:\k"
    .\kubelet-service.exe install

    $joinCommand = "C:\k\$(Get-Content C:\vagrant\join.sh -Raw)"
    Invoke-Expression $joinCommand
    start-service kubelet
}



[int]$retryCount = 0;
[bool]$success = $false

$command = { $( C:\k\kubectl.exe describe node $( hostname ).ToLower() | Select-String ovn_host_subnet ).Line.Split("{=}")[1] }
Do {
    try
    {
        $ovnHostSubnet=Invoke-Command -ScriptBlock $command -ErrorAction Stop
        $success = $true
    } catch {

        Write-Host "Node info not yet available from apiserver... sleeping 15s."
        $retryCount++
        Sleep 15
    }


} Until($retryCount -eq 6 -or $success)

if( ! $success ){
    Write-Host "Could not retrieve node info from apiserver"
    exit 1
}

echo "ovnHostSubnet: $ovnHostSubnet"

$gatewayIp="$($ovnHostSubnet -replace "(\d{1,3}\.\d{1,3}.\d{1,3}\.).*", '$1')1"
echo "gatewayIp: $gatewayIp"

$ipAddress = (Get-NetIPConfiguration  | where {$_.InterfaceAlias -eq $networkInterfaceAlias }).ipv4address.ipaddress
Write-Host "ipAddress: $ipAddress"

docker network create -d transparent --gateway $gatewayIp --subnet $ovnHostSubnet -o com.docker.network.windowsshim.interface="$networkInterfaceAlias" external
sleep 2;
$a = Get-NetAdapter | where Name -Match HNSTransparent
Rename-NetAdapter $a[0].Name -NewName HNSTransparent
Stop-Service ovs-vswitchd -force; Disable-VMSwitchExtension "Cloudbase Open vSwitch Extension";
ovs-vsctl --no-wait del-br br-ex
ovs-vsctl --no-wait --may-exist add-br br-ex
ovs-vsctl --no-wait add-port br-ex HNSTransparent -- set interface HNSTransparent type=internal
ovs-vsctl --no-wait add-port br-ex "$networkInterfaceAlias"
Get-VMSwitch -SwitchType External | Enable-VMSwitchExtension "Cloudbase Open vSwitch Extension"; sleep 2; Restart-Service ovs-vswitchd

$GUID = (New-Guid).Guid
ovs-vsctl set Open_vSwitch . external_ids:system-id="$($GUID)"

Start-BitsTransfer https://raw.githubusercontent.com/bsteciuk/k8s-ovn-windows-cluster/master/ovn_k8s.conf-windows -Destination "$env:OVS_SYSCONFDIR"


Add-Content C:\Windows\System32\drivers\etc\hosts "`r`n$ipAddress $(hostname)"

if ($vagrant) {

    C:\cni\ovnkube.exe -k8s-apiserver "https://$masterIp`:6443" `
        -k8s-cacert "C:\etc\kubernetes\pki\ca.crt" `
        -init-node "$($(hostname).ToLower())" `
        -k8s-token "$(Get-Content C:\vagrant\token)" `
        -nb-address "tcp://$masterIp`:6641" `
        -sb-address "tcp://$masterIp`:6642" `
        -cluster-subnet "$clusterSubnet" `
        -cni-conf-dir "C:\cni-conf" `
        -service-cluster-ip-range "$serviceClusterIpRange"

    Write-Host "ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-ip=$ipAddress"

    ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-ip="$ipAddress"

}

Start-BitsTransfer https://raw.githubusercontent.com/bsteciuk/k8s-ovn-windows-cluster/master/ovn_k8s.conf-windows -Destination "$env:OVS_SYSCONFDIR/ovn_k8s.conf"
