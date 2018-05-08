
 <#
.SYNOPSIS  
    Configures windows worker node
.LINK  
    https://github.com/bsteciuk/k8s-ovn-windows-cluster
    https://kubernetes.io/docs/getting-started-guides/windows/
.EXAMPLE  
   .\configure-windows.ps1 -gatewayIp 192.168.3.1 -ovnHostSubnet 192.168.3.0/24 -networkInterfaceAlias "Ethernet 2"
.FUNCTIONALITY  
   Not sure How to specify or use  
   Does not appear in basic, -full, or -detailed  
   Should appear with -functionality  
.PARAMETER gatewayIp  
   The first IP on the ovnHostSubnet , e.g. 192.168.3.1
.PARAMETER ovnHostSubnet  
   The subnet that comes back from kubectl describe node "<WINDOWS_HOSTNAME>" | grep ovn_host_subnet
   after the windows node is initialized, e.g. 192.168.3.0/24
.PARAMETER networkInterfaceAlias  
   The network interface name that is provisioned for the cluster , what
   comes back from ipconfig for the "external" interface where this node is accessible
   , e.g. "Ethernet 2"
#>
 
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

