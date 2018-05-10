
#bcdedit /set testsigning yes
#
#$ovsCertsLink = "https://docs.google.com/uc?export=download&id=1tGbGalZ6gDQOgjQuWAfIqGCNy-9RTpAF"
#
#$certLocation = "C:\certificate.cer"
#
#curl "$ovsCertsLink" -UseBasicParsing -o $certLocation
#
#$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$certLocation")
#$rootStore = Get-Item cert:\LocalMachine\TrustedPublisher
#$rootStore.Open("ReadWrite")
#$rootStore.Add($cert)
#$rootStore.Close()
#$rootStore = Get-Item cert:\LocalMachine\Root
#$rootStore.Open("ReadWrite")
#$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$certLocation")
#$rootStore.Add($cert)
#$rootStore.Close()

#cmd /c 'msiexec /i C:\openvswitch-hyperv-installer-beta.msi ADDLOCAL="OpenvSwitchServices,OpenvSwitchCLI,OpenvSwitchDriver,OVNHost" /qn'
cmd /c 'msiexec /i C:\openvswitch-hyperv-2.7.0-certified.msi ADDLOCAL="OpenvSwitchCLI,OpenvSwitchDriver,OVNHost" /qn'
echo $?
