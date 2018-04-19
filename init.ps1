netsh advfirewall set AllProfiles state off
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

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://github.com/kohsuke/winsw/releases/download/winsw-v2.1.2/WinSW.NET4.exe -OutFile C:\k\kubelet-service.exe

Start-BitsTransfer http://www.7-zip.org/a/7z1604-x64.exe
cmd /c '7z1604-x64.exe /S /qn'
Remove-Item -Recurse -Force 7z1604-x64.exe

Start-BitsTransfer https://dl.k8s.io/v1.10.0/kubernetes-node-windows-amd64.tar.gz

Start-BitsTransfer https://cloudbase.it/downloads/openvswitch-hyperv-installer-beta.msi

$serviceFileText=@"
<service>
      <id>kubelet</id>
      <name>kubelet</name>
      <description>This service runs kubelet.</description>
      <executable>C:\k\kubelet.exe</executable>
      <arguments>--hostname-override=$(hostname) --v=6 --pod-infra-container-image=apprenda/pause --resolv-conf="" --allow-privileged=true --enable-debugging-handlers --cluster-dns=10.96.0.10 --cluster-domain=cluster.local --bootstrap-kubeconfig="C:\etc\kubernetes\bootstrap-kubelet.conf" --kubeconfig=c:\k\config --hairpin-mode=promiscuous-bridge --image-pull-progress-deadline=20m --cgroups-per-qos=false --enforce-node-allocatable="" --network-plugin=cni --cni-bin-dir="c:\cni" --cni-conf-dir "c:\cni-conf"</arguments>
      <logmode>rotate</logmode>
</service>
"@

$serviceFileText | Out-File 'C:\k\kubelet-service.xml'


& 'C:\Program Files\7-Zip\7z.exe' e .\kubernetes-node-windows-amd64.tar.gz
& 'C:\Program Files\7-Zip\7z.exe' e .\kubernetes-node-windows-amd64.tar

cp C:\kubelet.exe C:\k
cp C:\kubeadm.exe C:\k

rm C:\kubernetes-node-windows-amd64.tar, C:\kubernetes-node-windows-amd64.tar.gz, C:\kubernetes-src.tar.gz, C:\LICENSES, C:\kubelet.exe, C:\kubeadm.exe, C:\kubectl.exe, C:\kube-proxy.exe

