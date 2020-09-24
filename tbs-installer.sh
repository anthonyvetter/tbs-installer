#!/bin/bash
set -e
set -u
set -o pipefail

PIVNET_API_TOKEN=unset
DH_USERNAME=unset
DH_PASSWORD=unset
GH_USERNAME=unset
GH_PASSWORD=unset
PR_USERNAME=unset
PR_PASSWORD=unset
ERROR_EXIT=false

usage()
{
  echo " 
  Installs Tanzu Build Service on to your Kubernetes Cluster. 
  Currently supported image repositories: Docker Hub
  Currently supported code repositories: GitHub
  Currently supported platforms: MacOS/Darwin
  Issues:
    - doesn't validate required flags are set
    - doesn't validate arguements have any input

  Usage:     
    --pivnet-api-token          (required)                  PivNet API token used for 'pivnet login --api-token'
    --dockerhub-username        (required)                  Your Docker Hub username
    --dockerhub-password        (required)                  Your Docker Hub password
    --pivotal-registry-username (required)                  Username used to login to registry.pivotal.io
    --pivotal-registry-password (required)                  Password used to login to registry.pivotal.io
    -h, --help                                              Print the help message"
  exit 2
}

while [[ $# -gt 0 ]] 
  do
    case "$1" in
      --pivnet-api-token)
        export PIVNET_API_TOKEN=$2
        ;;

      --dockerhub-username)
        export DH_USERNAME=$2
        ;;

      --dockerhub-password)
        export DH_PASSWORD=$2
        ;;

      --pivotal-registry-username)
        export PR_USERNAME=$2
        ;;
      --pivotal-registry-password)
        export PR_PASSWORD=$2
        ;;

      -h | --help)
        usage
        ;;

      -?*)
        printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
  shift
done

printf '\n\e[1;34m%-6s\e[m%s\n' "SETTING UP ENVIRONMENT" 
printf '\e[1;34m%-6s\e[m\n%s'   "======================"
export LOCAL_USER=$(id -un)

printf '\n\e[1;34m%-6s\e[m%s\n' "INSTALLING PIVNET" 
printf '\e[1;34m%-6s\e[m\n%s'   "================="
wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v2.0.1/pivnet-darwin-amd64-2.0.1
mv pivnet-darwin-amd64-2.0.1 pivnet
chmod +x pivnet
mv pivnet /usr/local/bin/
pivnet login --api-token=$PIVNET_API_TOKEN

printf '\n\e[1;34m%-6s\e[m%s\n' "DOWNLOADING TBS" 
printf '\e[1;34m%-6s\e[m\n%s'   "==============="
pivnet download-product-files --product-slug='build-service' --release-version='1.0.2' --product-file-id=773503
tar xvf build-service-1.0.2.tar

printf '\n\e[1;34m%-6s\e[m%s\n' "PREPPING INSTALL" 
printf '\e[1;34m%-6s\e[m\n%s'   "================"
echo "name: build-service-credentials
credentials:
- name: kube_config
  source:
    path: \"/Users/$LOCAL_USER/.kube/config\"
  destination:
    path: \"/root/.kube/config\"" > credentials.yml
echo "credentials file created \n"
printf '\n\e[1;34m%-6s\e[m%s\n' "LOGGING INTO DOCKER" 
printf '\e[1;34m%-6s\e[m\n%s'   "==================="
docker login -u $DH_USERNAME -p $DH_PASSWORD
docker login registry.pivotal.io -u $PR_USERNAME -p $PR_PASSWORD

printf '\n\e[1;34m%-6s\e[m%s\n' "PUSHING TBS IMAGES TO DOCKER" 
printf '\e[1;34m%-6s\e[m\n%s'   "============================"
kbld relocate -f images.lock --lock-output images-relocated.lock --repository $DH_USERNAME/tanzu-build-service

printf '\n\e[1;34m%-6s\e[m%s\n' "INSTALLING TANZU BUILD SERVICE" 
printf '\e[1;34m%-6s\e[m\n%s'   "=============================="
ytt -f values.yaml \
    -f manifests \
    -v docker_repository=$DH_USERNAME \
    -v docker_username="$DH_USERNAME" \
    -v docker_password="$DH_PASSWORD" \
    | kbld -f images-relocated.lock -f- \
    | kapp deploy -a tanzu-build-service -f- -y

printf '\n\e[1;34m%-6s\e[m%s\n' "INSTALLING KP" 
printf '\e[1;34m%-6s\e[m\n%s'   "============="
pivnet download-product-files --product-slug='build-service' --release-version='1.0.2' --product-file-id=773504
mv kp-darwin-0.1.1 kp
chmod +x kp
mv kp /usr/local/bin

printf '\n\e[1;34m%-6s\e[m%s\n' "INSTALLING TANZU BUILD SERVICE DEPENDENCIES" 
printf '\e[1;34m%-6s\e[m\n%s'   "==========================================="
pivnet download-product-files --product-slug='tbs-dependencies' --release-version='17' --product-file-id=793227
kp import -f descriptor-17.yaml

printf '\n\e[1;34m%-6s\e[m%s\n' "CLEANING UP FILES" 
printf '\e[1;34m%-6s\e[m\n%s'   "================="
rm -r manifests
rm build-service-*.tar
rm credentials.yml
rm descriptor-17.yaml
rm images-relocated.lock
rm images.lock
rm pivnet-darwin*
rm values.yaml