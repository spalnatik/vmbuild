#!/bin/bash

timestamp=$(date +"%Y-%m-%d %H:%M:%S")

echo "Script execution started at: $timestamp"

#set -x


rgname="Lab_Azure_Foundations"
offer="RedHat:RHEL:7_9:latest"
STORAGEACCOUNTNAME="fuseshare25"
loc="eastus"
sku_size="Standard_B1s"
Networksecuritygroup="Lab_Azure_Foundations-vnet-default-nsg-eastus"
logfile="ADE.log"

# Parse command line arguments
while getopts "i:" opt; do
  case $opt in
    i) offer=$OPTARG ;;
    *) ;;
  esac
done

echo "Offer: $offer"

if [ -f "./username.txt" ]; then
    username=$(cat username.txt)
else
    read -p "Please enter the username: " username
fi

if [ -f "./password.txt" ]; then
    password=$(cat password.txt)
else
    read -s -p "Please enter the password: " password
fi

echo ''

read -p "Please enter the vmname: " vmname


function check_resource_group_exists {
    az group show --name "$1" &> /dev/null
}

read -p "Enter the number of disks to attach: " num_disks

if [ $num_disks -gt 0 ]; then

    read -p "Enter FSType of disks: " ftype
fi

echo ""
date >> "$logfile"

if check_resource_group_exists "$rgname"; then
    echo "Resource group '$rgname' already exists. Skipping RG creation..."
else
    echo "Creating RG $rgname.."
    az group create --name "$rgname" --location "$loc" >> "$logfile"
fi

echo "Creating VM"

az vm create -g "$rgname" -n "$vmname" --admin-username "$username" --admin-password "$password" --image "$offer" --nsg ${Networksecuritygroup} --public-ip-sku Standard --size "$sku_size" >> "$logfile"

echo "Enable boot diagnostics"

az vm boot-diagnostics enable --name "$vmname" --resource-group "$rgname"

if [ $num_disks -gt 0 ]; then
    for ((i=1; i<=num_disks; i++))
    do
        disk_name="$vmname$i"
        size_gb=4

        az vm disk attach \
            -g "$rgname" \
            --vm-name "$vmname" \
            --name "$disk_name" \
            --new \
            --size-gb "$size_gb"

        if [ $? -eq 0 ]; then
            echo "Disk $disk_name successfully attached."
        else
            echo "Failed to attach disk $disk_name."
        fi
    done
fi


if [ $num_disks -gt 0 ]; then
    echo "format the newly attached disks"
    az vm extension set \
    --resource-group $rgname \
    --vm-name $vmname \
    --name customScript \
    --publisher Microsoft.Azure.Extensions \
    --protected-settings "{\"fileUris\": [\"https://raw.githubusercontent.com/spalnatik/ADE/main/format.sh\"],\"commandToExecute\": \"./format.sh $ftype\"}" >> $logfile
fi


echo 'Updating NSGs with public IP and allowing ssh access from that IP'
my_pip=`curl ifconfig.io`
nsg_list=`az network nsg list -g $rgname  --query [].name -o tsv`
for i in $nsg_list
do
        az network nsg rule create -g $rgname --nsg-name $i -n buildInfraRule --priority 100 --source-address-prefixes $my_pip  --destination-port-ranges 22 --access Allow --protocol Tcp >> $logfile
done


end_time=$(date +"%Y-%m-%d %H:%M:%S")

echo "Script execution completed at: $end_time"
