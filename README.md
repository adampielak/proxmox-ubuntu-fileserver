# Proxmox Ubuntu CT File Server (NAS)
The Ubuntu File Server is supported by a Proxmox ZFS Raid hosted on a Proxmox node (typhoon-01). Data is served by a Proxmox Ubuntu 18.04 CT (cyclone-01) installed with network protocols like NFS, samba and configured to manage all user accounts, file security and permissions and more.

The following is for creating a Proxmox Ubuntu CT File Server built on our primary Proxmox node typhoon-01.

Network Prerequisites are:
- [x] Layer 2 Network Switches
- [x] Network Gateway is `192.168.1.5`
- [x] Network DNS server is `192.168.1.5` (Note: your Gateway hardware should enable you to a configure DNS server(s), like a UniFi USG Gateway, so set the following: primary DNS `192.168.1.254` which will be your PiHole server IP address; and, secondary DNS `1.1.1.1` which is a backup Cloudfare DNS server in the event your PiHole server 192.168.1.254 fails or is down)
- [x] Network DHCP server is `192.168.1.5`

Mandantory Prerequisites are:
- [x] Proxmox node built and configured as per [PROXMOX-NODE BUILDING](https://github.com/ahuacate/proxmox-node/blob/master/README.md#proxmox-node-building)
- [x] Proxmox node configured with SSD ZFS Cache
- [x] Proxmox node installed with a minimum of 16Gb of RAM (Recommend 32Gb EEC Ram)
- [x] Proxmox node installed with a minimum of 3x NAS certified rotational hard disks

Other Prerequisites are:
- [x] UniFi network is fully configured as per [UNIFIBUILD](https://github.com/ahuacate/unifibuild)
- [x] pfSense is fully configured on typhoon-01 including steps [PFSENSE-SETUP](https://github.com/ahuacate/pfsense-setup) and [PFSENSE-HAPROXY](https://github.com/ahuacate/pfsense-haproxy)

Tasks to be performed are:
- [About LXC Homelab Installations](#about-lxc-homelab-installations)



## 1.00 Hardware and System Prerequisites

### 1.01 Proxmox Host Installed Memory RAM
ZFS depends heavily on memory, so you need at least 16GB to start (Recommend 32GB). In practice, use as much you can get for your hardware/budget. To prevent data corruption, we recommend the use of high quality ECC RAM (if your mainboard supports EEC).

### 1.02 Proxmox Host SSD Cache
ZFS allows for tiered caching of data through the use of memory.

It is recommend you setup two SSD caches so your ZFS pool can make use of for High Speed disk I/O:

*  ZFS Intent Log, or ZIL, to buffer WRITE operations.
*  ARC and L2ARC which are meant for READ operations.

We recommend you leave some unallocated disk space on your Proxmox nodes SSD for ZFS Cache. But you can also install dedicated SSDs in your node for the task.

**Proxmox VE SSD ZFS Cache Setup - Recommended**

You must configure your Ubuntu CT NAS host Proxmox VE installation in accordance with our instructions shown here:

*  [2.01 Proxmox VE OS Install - Build Type A](https://github.com/ahuacate/proxmox-node/blob/master/README.md#201-proxmox-ve-os-install---build-type-a)
*  [2.05 Partition Hard Drive(s) - Build Type A](https://github.com/ahuacate/proxmox-node/blob/master/README.md#205-partition-hard-drives---build-type-a)

If you followed our instructions [2.01](https://github.com/ahuacate/proxmox-node/blob/master/README.md#201-proxmox-ve-os-install---build-type-a) you would've resized your PVE installation to leave unallocated disk space on your Proxmox host SSD(s). This unallocated space is required for partitioning for ZFS Logs and Cache shown in the step [2.05](https://github.com/ahuacate/proxmox-node/blob/master/README.md#205-partition-hard-drives---build-type-a).




* Mandantory Prerequisite (A) - Proxmox Host RAM
  Minimum of 16GB. Recommend 32Gb RAM.
*  Optional Prerequisites (B-C) - ZFS Cache.
  You can either create ZFS Cache using your Proxmox PVE host SSD(s) by allocating some spare space OR install one or more dedicated SSD(s) for ZFS Cache. We HIGHLY RECOMMEND Prerequisite (A) solution using your Proxmox PVE host SSD(s) spare space for ZFS Cache. This is the most cost effective disk solution.
*  Mandantory Prerequisite (D) - Installation of Storage Disks
  You require empty storage disks to create your ZFS storage pool. You cannot mix SSD and rotating disk drives. We recommend you install at least 3x certified NAS hard disks of equal capacity as a minimum. During installation all data on the hard disks will be destroyed and is not recoverable!
