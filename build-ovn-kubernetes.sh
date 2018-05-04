# Run this script to biuld ovn-kubernetes
# when you're done, put this into a release in github and update init.sh with the rev/URL of this build
#Get, build, and install ovn-kubernetes
mkdir -p .build
cd .build
git clone https://github.com/openvswitch/ovn-kubernetes

cd ovn-kubernetes/go-controller

#We are switching to PR with fixes for windows RTM
git fetch origin pull/288/head:PR-288
git checkout PR-288
echo "Building ovn-kubernetes binaries... this may take a few minutes."
make all

ovnk8sVersion=$(git rev-parse --short HEAD)
cd _output/go/
tar -czvf ../../../../ovn-kubernetes-rev-${ovnk8sVersion}.tar.gz bin/* 