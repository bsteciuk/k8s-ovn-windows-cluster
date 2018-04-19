
 param (
    [Parameter(Mandatory=$true)][string]$gatewayIp,
    [Parameter(Mandatory=$true)][string]$ovnHostSubnet,
    [Parameter(Mandatory=$true)][string]$networkInterfaceAlias
 )



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

Start-BitsTransfer https://raw.githubusercontent.com/bsteciuk/k8s-ovn-windows-cluster/master/ovn_k8s.conf-windows -Destination 'C:\Program Files\Cloudbase Solutions\Open vSwitch\conf\ovn_k8s.conf'

