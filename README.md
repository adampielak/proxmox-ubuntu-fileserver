# Proxmox Ubuntu CT File Server (NAS)
The Ubuntu File Server is supported by a Proxmox ZFS Raid hosted on a Proxmox node (typhoon-01). Data is served by a Proxmox Ubuntu 18.04 CT (cyclone-01) installed with network protocols like NFS, samba and configured to manage all user accounts, file security and permissions and more.

The following is for creating a Proxmox Ubuntu CT File Server built on our primary Proxmox node typhoon-01.

Network Prerequisites are:
- [x] Layer 2 Network Switches
- [x] Network Gateway is `192.168.1.5`
- [x] Network DNS server is `192.168.1.5` (Note: your Gateway hardware should enable you to a configure DNS server(s), like a UniFi USG Gateway, so set the following: primary DNS `192.168.1.254` which will be your PiHole server IP address; and, secondary DNS `1.1.1.1` which is a backup Cloudfare DNS server in the event your PiHole server 192.168.1.254 fails or is down)
- [x] Network DHCP server is `192.168.1.5`
- [x] UniFi network is fully configured as per [UNIFIBUILD](https://github.com/ahuacate/unifibuild)

Mandantory Prerequisites are:
- [x] Proxmox node built and configured as per [PROXMOX-NODE BUILDING](https://github.com/ahuacate/proxmox-node/blob/master/README.md#proxmox-node-building)
- [x] Proxmox node installed with a minimum of 16Gb of RAM (Recommend 32Gb EEC Ram)
- [x] Proxmox node installed with a minimum of 3x NAS certified rotational hard disks

Optional Prerequisites are:
- [x] Proxmox node configured with SSD ZFS Cache (Highly Recommended)
- [x] You have a working SMTP mail server account (We recommend mailgun.com)
- [x] pfSense is fully configured including steps [PFSENSE-SETUP](https://github.com/ahuacate/pfsense-setup) and [PFSENSE-HAPROXY](https://github.com/ahuacate/pfsense-haproxy)

Tasks to be performed are:
- [About LXC Homelab Installations](#about-lxc-homelab-installations)



## 1.00 Hardware and System Prerequisites

### 1.01 Proxmox Host installed Memory RAM
ZFS depends heavily on memory, so you need at least 16GB to start (Recommend 32GB). In practice, use as much you can get for your hardware/budget. To prevent data corruption, we recommend the use of high quality ECC RAM (if your mainboard supports EEC).

### 1.02 Proxmox Host SSD Cache
ZFS allows for tiered caching of data through the use of memory.

It is recommend you setup two SSD caches so your ZFS pool can make use of cache for High Speed disk I/O:

*  ZFS Intent Log, or ZIL, to buffer WRITE operations.
*  ARC and L2ARC which are meant for READ operations.

**Proxmox VE SSD ZFS Cache Setup - Recommended**

We recommend you leave some unallocated disk space on your Proxmox VE node SSD for ZFS Cache instead of using a dedicated ZFS Cache SSD. This is the most cost effective disk solution. But you must configure your Ubuntu CT NAS host Proxmox VE installation in accordance with our instructions shown here:

*  [2.01 Proxmox VE OS Install - Build Type A](https://github.com/ahuacate/proxmox-node/blob/master/README.md#201-proxmox-ve-os-install---build-type-a)
*  [2.05 Partition Hard Drive(s) - Build Type A](https://github.com/ahuacate/proxmox-node/blob/master/README.md#205-partition-hard-drives---build-type-a)

If you followed our instructions [2.01](https://github.com/ahuacate/proxmox-node/blob/master/README.md#201-proxmox-ve-os-install---build-type-a) you would've resized your PVE installation to leave unallocated disk space on your Proxmox host SSD(s). This unallocated space is required for partitioning for ZFS Logs and Cache shown in the step [2.05](https://github.com/ahuacate/proxmox-node/blob/master/README.md#205-partition-hard-drives---build-type-a).

Also make sure your Proxmox VE node SSD are enterprise class SSD(s). Standard consumer grade SSD will wear out fast.

**Dedicated SSD ZFS Cache Setup**

This is the more costly solution. 

If you choose not use your hosts Proxmox VE SSD(s) for ZFS Cache then you can install 2x dedicated SSD disks for the task. These SSD disk need not be larger than 120GB but must be of identical size. Again we warn, during installation all data on the SSD disks will be destroyed and is not recoverable!

If you use a dedicated cache and/or log disk, you should use an enterprise class SSD. Standard consumer grade SSD will wear out fast.


### 1.03 Installation of Storage Disks
We recommend you install a minimum of 3x NAS certified rotational hard disks in your host. In the next steps our build scripts will give you the option to create a ZFS Raid of your hard disks with the following options:

| ZFS Raid Type | Description
| :---  | :--- 
|**RAID0**|Also called “striping”. No redundancy, so the failure of a single drive makes the volume unusable.
|**RAID1**|Also called “mirroring”. Data is written identically to all disks. The resulting capacity is that of a single disk.
|**RAID10**|A combination of RAID0 and RAID1. Requires at least 4 disks.
|**RAIDZ1**|A variation on RAID-5, single parity. Requires at least 3 disks.
|**RAIDZ2**|A variation on RAID-5, double parity. Requires at least 4 disks.
|**RAIDZ3**|A variation on RAID-5, triple parity. Requires at least 5 disks.


