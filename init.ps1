param (
    [Parameter(Mandatory=$false)][string]$networkInterfaceAlias
)

netsh advfirewall set AllProfiles state off
# The netkvm commands will fail in a local install
# These are relevant only if running in GCP
netsh netkvm setparam 0 *RscIPv4 0
netsh netkvm restart 0

#Install required packages
Install-WindowsFeature -Name Containers
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

cd C:\

mkdir C:\cni
mkdir C:\k
mkdir C:\cni-conf

Add-Content -Path 'C:\cni-conf\ovn-k8s-cni-overlay.conf' -Value '{"name":"ovn-kubernetes", "type":"ovn-k8s-cni-overlay"}' -Encoding Ascii

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://github.com/kohsuke/winsw/releases/download/winsw-v2.1.2/WinSW.NET4.exe -OutFile C:\k\kubelet-service.exe
Invoke-WebRequest -Uri https://github.com/bsteciuk/k8s-ovn-windows-cluster/raw/master/windows-k8s-bin.zip -OutFile C:\windows-k8s-bin.zip

Expand-Archive C:\windows-k8s-bin.zip
cp C:\windows-k8s-bin\windows-k8s-bin\ovn-k8s-cni-overlay.exe C:\cni
cp C:\windows-k8s-bin\windows-k8s-bin\ovnkube.exe C:\cni



Start-BitsTransfer http://www.7-zip.org/a/7z1604-x64.exe
cmd /c '7z1604-x64.exe /S /qn'
Remove-Item -Recurse -Force 7z1604-x64.exe

Start-BitsTransfer https://dl.k8s.io/v1.10.0/kubernetes-node-windows-amd64.tar.gz
#curl "https://docs.google.com/uc?export=download&id=1QnAtn8EhfbBFwn-1KPCkJ4EqCmEiT8g_" -UseBasicParsing -o "C:\openvswitch-hyperv-installer-beta.msi"

Start-BitsTransfer https://cloudbase.it/downloads/openvswitch-hyperv-installer-beta.msi
Start-BitsTransfer https://cloudbase.it/downloads/openvswitch-hyperv-2.7.0-certified.msi

$nodeIp=$(
    if (!$networkInterfaceAlias){""}
    else {"--node-ip $((Get-NetIPConfiguration  | where {$_.InterfaceAlias -eq "$networkInterfaceAlias" }).ipv4address.ipaddress)"}
)


$serviceFileText=@"
<service>
      <id>kubelet</id>
      <name>kubelet</name>
      <description>This service runs kubelet.</description>
      <executable>C:\k\kubelet.exe</executable>
      <arguments>--hostname-override=$(hostname) --v=6 $nodeIp --pod-infra-container-image=apprenda/pause --resolv-conf="" --allow-privileged=true --enable-debugging-handlers --cluster-dns=10.96.0.10 --cluster-domain=cluster.local --bootstrap-kubeconfig="C:\etc\kubernetes\bootstrap-kubelet.conf" --kubeconfig=c:\k\config --hairpin-mode=promiscuous-bridge --image-pull-progress-deadline=20m --cgroups-per-qos=false --enforce-node-allocatable="" --network-plugin=cni --cni-bin-dir="c:\cni" --cni-conf-dir "c:\cni-conf"</arguments>
      <logmode>rotate</logmode>
</service>
"@

$serviceFileText | Out-File 'C:\k\kubelet-service.xml'


& 'C:\Program Files\7-Zip\7z.exe' e .\kubernetes-node-windows-amd64.tar.gz
& 'C:\Program Files\7-Zip\7z.exe' e .\kubernetes-node-windows-amd64.tar

cp C:\windows-k8s-bin\windows-k8s-bin\kubelet.exe C:\k
cp C:\kubeadm.exe C:\k
cp C:\kubectl.exe C:\k
rm C:\kubernetes-node-windows-amd64.tar, C:\kubernetes-node-windows-amd64.tar.gz, C:\kubernetes-src.tar.gz, C:\LICENSES, C:\kubelet.exe, C:\kubeadm.exe, C:\kubectl.exe, C:\kube-proxy.exe


$vagrantDir = "C:\vagrant"
if(Test-Path -Path $vagrantDir ){
        mkdir C:\Users\$env:Username\.kube
        cp "$vagrantDir\admin.config" "C:\Users\$env:Username\.kube\config"
}

