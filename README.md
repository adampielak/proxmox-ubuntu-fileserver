# Proxmox Ubuntu CT File Server (NAS)
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



## 1.00 Hardware and System Specifications
The File Server is supported by a Proxmox ZFS Raid hosted on typhoon-01. Data is served by a Proxmox Ubuntu 18.04 CT (cyclone-01) hosted on node typhoon-01 installed with network protocols like NFS, samba and configured to manage all user accounts, file security and permissions and more.

### 1.01 Hardware prerequisites of the host computer
Here are the prequisites to build a Ubuntu CT File Server (NAS).

* Mandantory Prerequisite (A) - Proxmox Host RAM
  Minimum of 16GB. Recommend 32Gb RAM.
*  Optional Prerequisites (B-C) - ZFS Cache.
  You can either create ZFS Cache using your Proxmox PVE host SSD(s) by allocating some spare space OR install one or more dedicated SSD(s) for ZFS Cache. We HIGHLY RECOMMEND Prerequisite (A) solution using your Proxmox PVE host SSD(s) spare space for ZFS Cache. This is the most cost effective disk solution.
*  Mandantory Prerequisite (D) - Installation of Storage Disks
  You require empty storage disks to create your ZFS storage pool. You cannot mix SSD and rotating disk drives. We recommend you install at least 3x certified NAS hard disks of equal capacity as a minimum. During installation all data on the hard disks will be destroyed and is not recoverable!
