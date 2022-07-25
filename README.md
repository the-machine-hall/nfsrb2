# nfsrb2 (NFS root file system builder 2) #

Now bigger **and** better!

The tools in this repo allow to create NFS root file systems for OpenBSD and NetBSD from OpenBSD, NetBSD or GNU/Linux automagically.

## Prerequisites ##

**No** additional prerequisites required when working from a default OpenBSD installation.

## Features ##

* per host configuration files (e.g. `es45.openbsd.64.alpha.conf`)
* configuration value override via environment (i.e. `_OS_VERSION="7.1" nfsrb es45.openbsd.64.alpha.conf`)
* automatic file installation during *post actions* for e.g. authorized SSH keys, host keys, profile files, etc. via per-host, per-OS, per-platform or generic trees (for details see `addFiles()`)
* manual creation of keys for OpenSSH, *SSL via separate tool (`gen-keys-openbsd`, ATM for OpenBSD only)
* Integrity checks for downloaded files
* Validity checks for downloaded files (for OpenBSD only, since OpenBSD 5.5 and requires `signify` and corresponding public keys)
* "Caching" of already downloaded files

## How to use ##

1. Create a configuration for the NFS rootfs creation process (see [`machine-name.conf.example`] for an example)

[`machine-name.conf.example`]: /share/doc/machine-name.conf.example

2. Prefill your additional files tree(s):

   ```
   root@nfs:~/nfsrb-configurations# tree ../.nfsrb/
   ../.nfsrb/
   901356f49fdfe84dd20df4e30f5035c612ac69097daca10e6b47cd05c9149bc1.tmpdir
   [...]
   └── add-files
       └── GENERIC
           └── root
               └── .ssh
                   └── authorized_keys
   ```

3. Start the creation process (you need to be `root`!):
   
   ```
   root@nfs:~/nfsrb-configurations# _OS_VERSION="7.1" nfsrb es45.openbsd.64.alpha.conf
   Now downloading files... [...] OK
   Now validating files... OK
   Now extracting sets... OK
   Now configuring file system:
   Installing kernel... OK
   Configuring swap space... OK
   Configuring network... OK
   Creating devices... Only created `/dev/console' as we're not running under OpenBSD. Please use root FS in single user mode and create devices manually (`mount -uw / && cd /dev && ./MAKEDEV all`) before going multi-user.
   Configuring file systems... OK
   Installing nfsrb marker files... OK
   Executing post actions... OK

   root@nfs:~/nfsrb-configurations# cd /srv/nfs/openbsd/7.1/alpha
   root@nfs:/srv/nfs/openbsd/7.1/alpha# tree
   .
   ├── base71.tgz
   ├── bsd.mp
   ├── comp71.tgz
   ├── hosts
   │   └── es45
   │       ├── root
   [...]
   │       └── swap
   ├── man71.tgz
   ├── netboot
   ├── SHA256
   └── SHA256.sig

   root@nfs:/srv/nfs/openbsd/7.1/alpha# cat -v hosts/es45/root/etc/nfsrb_openbsd_version 
   7.1 (unknown)
   ```
   > **NOTICE:** For target and host OpenBSD versions since 5.5 file validity can be checked with [`signify(1)`]. The builder uses `signify(1)` on OpenBSD 5.5 and greater and `sha256(1)` on OpenBSD 5.4 and smaller. On other OSes only the hash values are checked.

[`signify(1)`]: http://www.openbsd.org/cgi-bin/man.cgi/OpenBSD-5.5/man1/signify.1?query=signify&manpath=OpenBSD-5.5

4. Precreate OpenSSL/OpenSSH keys for the target system (only for OpenBSD for now)
   ```
   root@nfs:/srv/nfs/openbsd/7.1/alpha# gen-keys-openbsd.sh hosts/es45/root
   gen-keys-openbsd: Warning: Host OS is GNU/Linux. Generating available SSH key types of host OS only.
   gen-keys-openbsd: Generating keys...
   openssl: generating isakmpd/iked RSA key... done
   ssh-keygen: generating openssh keys... dsa ecdsa ed25519 rsa done
   ```
   > **NOTICE:** The key generation on the host comes in handy for slow target machines (e.g. SUN SPARCstation 10 or SPARCclassic) which need a considerable amount of time to create SSH keys. If your host OS is older than the target OS, or if it is NetBSD or GNU/Linux, you can still create the SSH key types that are available on your host OS. On first run the target machine will create the missing keys.

## License ##

(GPLv3)

Copyright (C) 2014-2022 Frank Scheiner

The software is distributed under the terms of the GNU General Public License

This software is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a [copy] of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

[copy]: /COPYING

