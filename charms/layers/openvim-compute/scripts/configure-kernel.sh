#!/bin/bash


# Huge pages 1G auto mount
mkdir -p /mnt/huge
if ! grep -q "Huge pages" /etc/fstab
then
 echo "" >> /etc/fstab
 echo "# Huge pages" >> /etc/fstab
 echo "nodev /mnt/huge hugetlbfs pagesize=1GB 0 0" >> /etc/fstab
 echo "" >> /etc/fstab
fi

# Grub virtualization options:

# Get isolcpus
isolcpus=`gawk 'BEGIN{pre=-2;}
 ($1=="processor"){pro=$3;}
 ($1=="core" && $4!=0){
    if (pre+1==pro){endrange="-" pro}
    else{cpus=cpus endrange sep pro; sep=","; endrange="";};
    pre=pro;}
 END{printf("%s",cpus endrange);}' /proc/cpuinfo`

# This fails on AWS and possibly other virtual machines, so we may need
# to follow a different path for those, like smartly building the kernel
# configuration based on the capabilities of the machine so that we can
# gracefully downgrade (e.g., for developer/test environments)
[[ $isolcpus -lt 0 || -z $isolcpus ]] && exit 1
echo "CPUS: $isolcpus"

# Huge pages reservation file: reserving all memory apart from 4GB per NUMA node
# Get the number of hugepages: all memory but 8GB reserved for the OS
#totalmem=`dmidecode --type 17|grep Size |grep MB |gawk '{suma+=$2} END {print suma/1024}'`
#hugepages=$(($totalmem-8))

if ! [ -f /usr/lib/systemd/hugetlb-reserve-pages ]
then
 cat > /usr/lib/systemd/hugetlb-reserve-pages << EOL
#!/bin/bash
nodes_path=/sys/devices/system/node/
if [ ! -d \$nodes_path ]; then
       echo "ERROR: \$nodes_path does not exist"
       exit 1
fi

reserve_pages()
{
       echo \$1 > \$nodes_path/\$2/hugepages/hugepages-1048576kB/nr_hugepages
}

# This example reserves all available memory apart from 4 GB for linux
# using 1GB size. You can modify it to your needs or comment the lines
# to avoid reserve memory in a numa node
EOL
 for f in /sys/devices/system/node/node?/meminfo
 do
   node=`head -n1 $f | gawk '($5=="kB"){print $2}'`
   memory=`head -n1 $f | gawk '($5=="kB"){print $4}'`
   memory=$((memory+1048576-1))   #memory must be ceiled
   memory=$((memory/1048576))   #from `kB to GB
   #if memory
   [ $memory -gt 4 ] && echo "reserve_pages $((memory-4)) node$node" >> /usr/lib/systemd/hugetlb-reserve-pages
 done

 # Run the following commands to enable huge pages early boot reservation:
 chmod +x /usr/lib/systemd/hugetlb-reserve-pages
 systemctl enable hugetlb-gigantic-pages
fi

# Prepares the text to add at the end of the grub line, including blacklisting ixgbevf driver in the host
hpages=0
for f in /sys/devices/system/node/node?/meminfo
do
  node=`head -n1 $f | gawk '($5=="kB"){print $2}'`
  memory=`head -n1 $f | gawk '($5=="kB"){print $4}'`
  memory=$((memory+1048576-1))   #memory must be ceiled
  memory=$((memory/1048576))   #from `kB to GB
  #if memory
  [ $memory -gt 4 ] && hpages=$((hpages+memory-4))
done

#memtotal=`grep MemTotal /proc/meminfo | awk '{ print $2 }' `
# hpages=$(( ($memtotal/(1024*1024))-8 ))
#
# memtotal=$((memtotal+1048576-1))   #memory must be ceiled
# memtotal=$((memtotal/1048576))   #from `kB to GBa
# hpages=$((memtotal-8))
# [[ $hpages -lt 0 ]] && hpages=0


#echo "------> memtotal: $memtotal"

textokernel="intel_iommu=on default_hugepagesz=1G hugepagesz=1G hugepages=$hpages isolcpus=$isolcpus modprobe.blacklist=ixgbevf modprobe.blacklist=i40evf"

echo "Text to kernel: $textokernel"

# Add text to the kernel line
if ! grep -q "intel_iommu=on default_hugepagesz=1G hugepagesz=1G" /etc/default/grub
then
 echo ">>>>>>>  adding cmdline ${textokernel}"
 # BUG: this should write to GRUB_CMDLINE_LINUX_DEFAULT but update-grub
 # isn't taking it into account.
 # sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"\$/${textokernel}\"/" /etc/default/grub
 sed -i "/^GRUB_CMDLINE_LINUX=/s/\"\$/${textokernel}\"/" /etc/default/grub
 update-grub
 juju-reboot --now
fi
