#!/usr/bin/env mksh
#
# Copyright © 2014-2024
#	Waldemar Brodkorb <wbx@openadk.org>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un‐
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided “AS IS” and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person’s immediate fault when using the work as intended.
#
# Alternatively, this work may be distributed under the Terms of the
# General Public License, any version as published by the Free Soft‐
# ware Foundation.

# uClibc-ng
arch_list_uclibcng="aarch64 aarch64be alpha arcv2 arc32 \
  armv5 armv5-nommu-arm armv5-nommu-thumb armv5-nommu-fdpic armv5-nommu-elf \
  armv6 armv7 armv7-thumb2 armv8 armv8-thumb2 armeb avr32 \
  bf512-flat bf512-fdpic bf532-flat bf532-fdpic \
  c6x crisv10 crisv32 csky-ck807 csky-ck810 \
  h8300-h8300h h8300-h8s hppa ia64 kvx lm32 \
  m68k m68k-nommu-flat m68k-nommu-elf metag microblazeel microblazebe \
  mips32 mips32r6 mips32sf mips32el mips32r6el mips32elsf \
  mips64 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 \
  mips64r6n32 mips64r6n64 mips64r6eln32 mips64r6eln64 nds32le \
  nios2 or1k ppc ppcsf riscv32 riscv32-nommu-flat riscv32-nommu-elf \
  riscv64 riscv64-nommu-flat riscv64-nommu-elf \
  sh2 sh2eb sh3 sh3eb sh4 sh4eb sparc sparc-leon3 sparc64 tilegx x86 x86_64 \
  xtensa xtensabe xtensa-nommu"

# musl
arch_list_musl="aarch64 aarch64be armv5 armv6 armv7 armeb \
  m68k microblazeel microblazebe \
  mips32 mips32r6 mips32sf mips32el mips32elsf \
  mips64n32 mips64n64 mips64eln32 mips64eln64 \
  or1k ppc ppcsf ppc64 ppc64le riscv32 riscv64 s390 sh4 sh4eb \
  x86 x86_64 x86_64_x32"

# glibc
arch_list_glibc="aarch64 aarch64be alpha armv7 arcv2 arc32 arc64 \
  csky-ck807 csky-ck810 ia64 m68k microblazeel microblazebe \
  mips32 mips32r6 mips32sf mips32el mips32elsf \
  mips64 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 \
  mips64r6n32 mips64r6n64 mips64r6eln32 mips64r6eln64 loongarch \
  nios2 or1k ppc ppcsf ppc64 ppc64le riscv32 riscv64 s390 sh4 sh4eb sparc64 \
  x86_64 x86_64_x32"

# newlib
arch_list_newlib="aarch64 aarch64be armv5 bfin crisv10 \
  crisv32 csky-ck807 epiphany ft32 frv h8300-h8300h ia64 m32r m68k microblazeel \
  microblazebe mips32 mips32el mn10300 moxie msp430 nds32le nds32be \
  nios2 or1k ppc riscv64 rx sh sparc v850 x86 x86_64 xtensa"

topdir=$(pwd)
giturl=git://openadk.org/git/openadk
valid_os="linux"
valid_libc="uclibc-ng musl glibc newlib"
valid_tests="toolchain boot libc ltp mksh native"
valid_thread_types="none lt nptl"

bootserver=10.0.0.1
buildserver=10.0.0.2

tools='make git gzip cpio tar awk sed'
f=0
for tool in $tools; do
  if ! which $tool >/dev/null; then
    echo "Checking if $tool is installed... failed"
    f=1
  fi
done
if [ $f -eq 1 ]; then 
  exit 1
fi

help() {
	cat >&2 <<EOF
Syntax: $0 [ --libc=<libc> --os=<os> --arch=<arch> --test=<test> ]

Explanation:
	--libc=<libc>                C library to use (${valid_libc})
	--os=<operating system>      operating system to use (${valid_os})
	--arch=<arch>                architecture to check (otherwise all supported)
	--skip-arch=<arch>           architectures to skip when all choosen
	--targets=<targets.txt>      a list of remote targets to test via nfsroot or chroot
	--test=<test>                run test (${valid_tests}), default toolchain
	--threads=<type>             configure threading support (${valid_thread_types}) (only for uClibc-ng)
	--libc-source=<dir>          use directory with source for C library
	--gcc-source=<dir>           use directory with source for gcc
	--binutils-source=<dir>      use directory with source for binutils
	--gdb-source=<dir>           use directory with source for gdb
        --kernel-source=<dir>        use directory with source for kernel
	--libc-version=<version>     use version of C library
	--gcc-version=<version>      use version of gcc
	--binutils-version=<version> use version of binutils
	--gdb-version=<version>      use version of gdb 
	--kernel-version=<version>   use version of kernel
	--ntp=<ntpserver>            set NTP server for test run
	--packages=<packagelist>     add extra packages to the build
	--update                     update OpenADK source via git pull, before building
	--create                     create toolchain archive for external usage
	--continue                   continue on a broken build
	--cleandir                   clean OpenADK build directories before build
	--clean                      clean OpenADK build directory for single arch
	--no-clean                   do not clean OpenADK build directory for single arch
	--cxx                        enable C++ toolchain
	--static                     use static compilation
	--ssp                        use smack stashing protection
	--debug                      make debug build
	--verbose                    enable verbose output from OpenADK
	--shell                      start a shell instead of test autorun
	--timestamp		     add a timestamp to REPORT
	--help                       this help text
EOF
	exit 1
}

cont=0
clean=0
noclean=0
cleandir=0
shell=0
update=0
verbose=0
create=0
static=0
cxx=0
ssp=0
debug=0
timestamp=0
ntp=""
libc=""
os="linux"
test="toolchain"

while [[ $1 != -- && $1 = -* ]]; do case $1 { 
  (--cleandir) cleandir=1; shift ;;
  (--clean) clean=1; shift ;;
  (--no-clean) noclean=1; shift ;;
  (--verbose) verbose=1; shift ;;
  (--update) update=1; shift ;;
  (--create) create=1; shift ;;
  (--static) static=1; shift ;;
  (--cxx) cxx=1; shift ;;
  (--ssp) ssp=1; shift ;;
  (--debug) debug=1; shift ;;
  (--continue) cont=1; shift ;;
  (--shell) shell=1 shift ;;
  (--timestamp) timestamp=1 shift ;;
  (--libc=*) libc=${1#*=}; shift ;;
  (--os=*) os=${1#*=}; shift ;;
  (--arch=*) archs=${1#*=}; shift ;;
  (--skip-arch=*) skiparchs=${1#*=}; shift ;;
  (--targets=*) targets=${1#*=}; shift ;;
  (--test=*) test=${1#*=}; shift ;;
  (--threads=*) threads=${1#*=}; shift ;;
  (--libc-source=*) libcsource=${1#*=}; shift ;;
  (--gcc-source=*) gccsource=${1#*=}; shift ;;
  (--binutils-source=*) binutilssource=${1#*=}; shift ;;
  (--gdb-source=*) gdbsource=${1#*=}; shift ;;
  (--kernel-source=*) kernelsource=${1#*=}; shift ;;
  (--libc-version=*) libcversion=${1#*=}; shift ;;
  (--gcc-version=*) gccversion=${1#*=}; shift ;;
  (--binutils-version=*) binutilsversion=${1#*=}; shift ;;
  (--gdb-version=*) gdbversion=${1#*=}; shift ;;
  (--kernel-version=*) kernelversion=${1#*=}; shift ;;
  (--packages=*) packages=${1#*=}; shift ;;
  (--ntp=*) ntp=${1#*=}; shift ;;
  (--help) help; shift ;;
  (--*) echo "unknown option $1"; exit 1 ;; 
  (-*) help ;;
}; done

if [ ! -z $targets ]; then
  targetmode=1
fi

if [ -z "$libc" ]; then
  if [[ $libcversion ]]; then
    echo "You can not use a specific C library version without setting the C library"
    exit 1
  else
    libc="uclibc-ng musl glibc newlib"
  fi
fi

if [ $static -eq 1 ]; then
  rsuffix=${rsuffix}.static
fi
if [ $ssp -eq 1 ]; then
  rsuffix=${rsuffix}.ssp
fi
if [ $debug -eq 1 ]; then
  rsuffix=${rsuffix}.debug
fi
if [ $cxx -eq 1 ]; then
  rsuffix=${rsuffix}.cxx
fi
if [ $timestamp -eq 1 ]; then
  rsuffix=${rsuffix}.$(date +%s)
fi

if [ ! -d openadk ]; then
  git clone $giturl
  if [ $? -ne 0 ]; then
    echo "Cloning from $giturl failed."
    exit 1
  fi
else
  if [ $update -eq 1 ]; then
    (cd openadk && git pull)
    if [ $? -ne 0 ]; then
      echo "Updating from $giturl failed."
      exit 1
    fi
  fi
fi

get_arch_info() {
  arch=$1
  lib=$2

  emulator=qemu
  gdbcmd=
  noappend=0
  piggyback=1
  disk=0
  endian=
  suffix=
  allowed_libc=
  runtime_test=
  qemu_args="-nographic"
  #qemu_args="-nographic -append debug"

  case ${arch} in
    aarch64)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-aarch64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-aarch64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-aarch64"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=aarch64"
      cpu_arch=cortex_a53
      qemu_machine=virt
      qemu_args="${qemu_args} -m 256 -cpu cortex-a53 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      suffix=${cpu_arch}
      skiplt=aarch64
      ;;
    aarch64be)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_SYSTEM=generic-aarch64 ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_SYSTEM=generic-aarch64 ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=aarch64 ADK_TARGET_SYSTEM=generic-aarch64 ADK_TARGET_ENDIAN=big"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=aarch64 ADK_TARGET_ENDIAN=big"
      cpu_arch=cortex_a53
      qemu_machine=virt
      qemu_args="${qemu_args} -cpu cortex-a53 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      suffix=${cpu_arch}
      skiplt=aarch64be
      ;;
    alpha)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc ltp mksh"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=alpha ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-alpha"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=alpha ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-alpha"
      march=alpha
      qemu=qemu-system-alpha
      qemu_machine=clipper
      qemu_args="${qemu_args} -monitor null -m 256"
      ;;
    armv5)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=arm ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=arm926ej-s"
      cpu_arch=arm926ej_s
      march=arm-versatilepb
      qemu=qemu-system-arm
      qemu_machine=versatilepb
      suffix=${cpu_arch}_soft_eabi_arm
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -cpu arm926 -net user -net nic,model=smc91c111 -dtb ${dtbdir}/versatile-pb.dtb"
      ;;
    armv5-nommu-arm)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no ADK_TARGET_INSTRUCTION_SET=arm ADK_TARGET_BINFMT=flat ADK_TARGET_THREADS=lt ADK_TARGET_FLOAT=soft"
      cpu_arch=arm926ej_s
      march=arm-versatilepb
      qemu=qemu-system-arm
      qemu_machine=versatilepb
      suffix=${cpu_arch}_soft_eabi_flat_arm_nommu
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -m 256 -cpu arm926 -net user -net nic,model=smc91c111 -dtb ${dtbdir}/versatile-pb.dtb"
      ;;
    armv5-nommu-thumb)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no ADK_TARGET_INSTRUCTION_SET=thumb ADK_TARGET_BINFMT=flat ADK_TARGET_THREADS=lt ADK_TARGET_FLOAT=soft"
      cpu_arch=arm926ej_s
      march=arm-versatilepb
      qemu=qemu-system-arm
      qemu_machine=versatilepb
      suffix=${cpu_arch}_soft_eabi_flat_thumb_nommu
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -m 256 -cpu arm926 -net user -net nic,model=smc91c111 -dtb ${dtbdir}/versatile-pb.dtb"
      ;;
    armv5-nommu-fdpic)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no ADK_TARGET_INSTRUCTION_SET=arm ADK_TARGET_BINFMT=fdpic ADK_TARGET_THREADS=none ADK_TARGET_FLOAT=soft"
      cpu_arch=arm926ej_s
      march=arm-versatilepb
      qemu=qemu-system-arm
      qemu_machine=versatilepb
      suffix=${cpu_arch}_soft_eabi_fdpic_arm_nommu
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -m 256 -cpu arm926 -net user -net nic,model=smc91c111 -dtb ${dtbdir}/versatile-pb.dtb"
      ;;
    armv5-nommu-elf)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-versatilepb ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no ADK_TARGET_INSTRUCTION_SET=arm ADK_TARGET_BINFMT=elf ADK_TARGET_THREADS=none ADK_TARGET_FLOAT=soft"
      cpu_arch=arm926ej_s
      march=arm-versatilepb
      qemu=qemu-system-arm
      qemu_machine=versatilepb
      suffix=${cpu_arch}_soft_eabi_elf_arm_nommu
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -m 256 -cpu arm926 -net user -net nic,model=smc91c111 -dtb ${dtbdir}/versatile-pb.dtb"
      ;;
    armv6)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-realview-eb-mpcore"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-realview-eb-mpcore"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-realview-eb-mpcore"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=arm ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=arm1176jzf-s"
      cpu_arch=mpcore
      march=arm-realview-eb-mpcore
      qemu=qemu-system-arm
      qemu_machine=realview-eb-mpcore
      suffix=${cpu_arch}_hard_eabihf_arm
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -net user -net nic -dtb ${dtbdir}/arm-realview-eb-11mp-ctrevb.dtb"
      ;;
    armv7)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      cpu_arch=cortex_a9
      march=arm-vexpress-a9
      qemu=qemu-system-arm
      qemu_machine=vexpress-a9
      suffix=${cpu_arch}_hard_eabihf_arm
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
      ;;
    armv7-thumb2)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_INSTRUCTION_SET=thumb ADK_TARGET_FS=initramfspiggyback ADK_TARGET_FLOAT=soft ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      cpu_arch=cortex_a9
      march=arm-vexpress-a9
      qemu=qemu-system-arm
      qemu_machine=vexpress-a9
      suffix=${cpu_arch}_soft_eabi_thumb
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${suffix}
      qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
      ;;
    armv8)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9 ADK_TARGET_CPU=cortex-a53"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9 ADK_TARGET_CPU=cortex-a53"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9 ADK_TARGET_CPU=cortex-a53"
      cpu_arch=cortex_a53
      suffix=${cpu_arch}_hard_eabihf_arm
      ;;
    armv8-thumb2)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_INSTRUCTION_SET=thumb ADK_TARGET_FS=initramfspiggyback ADK_TARGET_FLOAT=soft ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9 ADK_TARGET_CPU=cortex-a53"
      cpu_arch=cortex_a53
      suffix=${cpu_arch}_soft_eabi_thumb
      ;;
    armeb)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=generic-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=generic-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=generic-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      ;;
    arcv2)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=archs"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=archs"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=archs"
      qemu=qemu-system-arc
      qemu_machine=virt
      qemu_args="-nographic -monitor none -serial stdio -cpu archs -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      cpu_arch=archs
      march=arc
      suffix=${cpu_arch}
      ;;
    arc32)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=arc32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=arc32"
      qemu=qemu-system-arc
      qemu_machine=virt,ram_start=0
      qemu_args="-nographic -monitor none -serial stdio -cpu hs5x -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      march=arc
      ;;
    arc64)
      allowed_libc="glibc"
      runtime_test="glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-arc ADK_TARGET_ENDIAN=little ADK_TARGET_CPU=arc64"
      qemu=qemu-system-arc64
      qemu_machine=virt,ram_start=0
      qemu_args="-nographic -monitor none -serial stdio -cpu hs6x -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      march=arc
      ;;
    avr32)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=avr32 ADK_TARGET_SYSTEM=generic-avr32"
      ;;
    bf512-flat)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=bfin ADK_TARGET_SYSTEM=sim-bfin ADK_TARGET_BINFMT=flat"
      emulator=gdb
      model=bf512
      march=bfin
      binfmt=flat
      gdbcmd="bfin-openadk-uclinux-uclibc-run --env operating --model bf512"
      suffix=bf512_flat
      ;;
    bf512-fdpic)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=bfin ADK_TARGET_SYSTEM=sim-bfin ADK_TARGET_BINFMT=fdpic"
      emulator=gdb
      model=bf512
      march=bfin
      binfmt=fdpic
      gdbcmd="bfin-openadk-linux-uclibc-run --env operating --model bf512"
      suffix=bf512_fdpic
      ;;
    bf532-flat)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=bfin ADK_TARGET_CPU=bf532 ADK_TARGET_SYSTEM=sim-bfin ADK_TARGET_BINFMT=flat"
      emulator=gdb
      model=bf532
      march=bfin
      binfmt=flat
      gdbcmd="bfin-openadk-uclinux-uclibc-run --env operating --model bf532"
      suffix=bf532_flat
      ;;
    bf532-fdpic)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=bfin ADK_TARGET_CPU=bf532 ADK_TARGET_SYSTEM=sim-bfin ADK_TARGET_BINFMT=fdpic"
      emulator=gdb
      model=bf532
      march=bfin
      binfmt=fdpic
      gdbcmd="bfin-openadk-linux-uclibc-run --env operating --model bf532"
      suffix=bf532_fdpic
      ;;
    bfin)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=bfin"
      ;;
    c6x)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=c6x ADK_TARGET_SYSTEM=generic-c6x ADK_TARGET_ENDIAN=little"
      ;;
    crisv10)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=cris ADK_TARGET_SYSTEM=generic-cris ADK_TARGET_CPU=crisv10"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=cris ADK_TARGET_CPU=crisv10"
      ;;
    crisv32)
      allowed_libc="uclibc-ng newlib"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-cris"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=cris ADK_TARGET_CPU=crisv32"
      cpu_arch=crisv32
      march=cris
      qemu=qemu-system-${march}
      qemu_machine=axis-dev88
      suffix=${cpu_arch}
      ;;
    csky-ck807)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=csky ADK_TARGET_SYSTEM=qemu-csky ADK_TARGET_CPU=ck807 ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=csky ADK_TARGET_SYSTEM=qemu-csky ADK_TARGET_CPU=ck807 ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=csky ADK_TARGET_CPU=ck807 ADK_TARGET_ENDIAN=little"
      march=csky
      qemu=qemu-system-cskyv2
      qemu_args="-nographic -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      qemu_machine=virt
      suffix=soft
      skiplt=csky-ck807
      ;;
    csky-ck810)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=csky ADK_TARGET_SYSTEM=qemu-csky ADK_TARGET_CPU=ck810 ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=csky ADK_TARGET_SYSTEM=qemu-csky ADK_TARGET_CPU=ck810 ADK_TARGET_ENDIAN=little"
      march=csky
      qemu=qemu-system-cskyv2
      qemu_args="-nographic -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      qemu_machine=virt
      suffix=soft
      skiplt=csky-ck810
      ;;
    epiphany)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=epiphany"
      ;;
    ft32)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=ft32"
      ;;
    frv)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=frv ADK_TARGET_SYSTEM=generic-frv"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=frv"
      ;;
    ia64)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=ia64 ADK_TARGET_SYSTEM=generic-ia64"
      default_glibc="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=ia64 ADK_TARGET_SYSTEM=generic-ia64"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=ia64"
      ;;
    kvx)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=kvx ADK_TARGET_SYSTEM=qemu-kvx"
      qemu=qemu-system-kvx
      qemu_args="-nographic"
      qemu_machine=mppa-coolidge
      skiplt=kvx
      ;;
    h8300-h8300h)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=h8300 ADK_TARGET_CPU=h8300h ADK_TARGET_SYSTEM=sim-h8300"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=h8300 ADK_TARGET_CPU=h8300h"
      ;;
    h8300-h8s)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=h8300 ADK_TARGET_CPU=h8s ADK_TARGET_SYSTEM=sim-h8300"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=h8300 ADK_TARGET_CPU=h8s"
      ;;
    hppa)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=hppa ADK_TARGET_SYSTEM=qemu-hppa"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=hppa ADK_TARGET_SYSTEM=qemu-hppa"
      qemu=qemu-system-hppa
      qemu_args="-nographic -device e1000,netdev=adk0 -netdev user,id=adk0"
      qemu_machine=B160L
      ;;
    lm32)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=lm32 ADK_TARGET_SYSTEM=qemu-lm32"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=lm32"
      skipcxx=lm32
      ;;
    loongarch)
      allowed_libc="glibc"
      runtime_test="glibc"
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=loongarch ADK_TARGET_SYSTEM=qemu-loongarch"
      qemu=qemu-system-loongarch64
      qemu_machine=virt
      qemu_args='-nographic -bios target/loongarch/QEMU_EFI.fd -append console=ttyS0,115200'
      ;;
    m32r)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=m32r"
      ;;
    m68k)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-m68k-q800 ADK_TARGET_CPU=68040"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-m68k-q800 ADK_TARGET_CPU=68040"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-m68k-q800 ADK_TARGET_CPU=68040"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=m68k ADK_TARGET_CPU=68040"
      cpu_arch=68040
      march=m68k-q800
      qemu=qemu-system-m68k
      qemu_args="-nographic"
      qemu_machine=q800
      suffix=${cpu_arch}
      ;;
    m68k-nommu-flat)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-m68k-mcf5208 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=flat ADK_TARGET_THREADS=lt"
      cpu_arch=cf5208
      march=m68k-mcf5208
      qemu=qemu-system-m68k
      qemu_args="-nographic -m 256"
      qemu_machine=mcf5208evb
      suffix=${cpu_arch}_flat_nommu
      ;;
    m68k-nommu-elf)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-m68k-mcf5208 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=elf ADK_TARGET_THREADS=none"
      cpu_arch=cf5208
      march=m68k-mcf5208
      qemu=qemu-system-m68k
      qemu_args="-nographic -m 256"
      qemu_machine=mcf5208evb
      suffix=${cpu_arch}_elf_nommu
      ;;
    metag)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=metag ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-metag"
      cpu_arch=metag
      qemu=qemu-system-meta
      qemu_args="-nographic -display none -device da,exit_threads=1 -chardev stdio,id=chan1 -chardev pty,id=chan2"
      qemu_machine=01sp
      skiplt=metag
      skipstatic=metag
      ;;
    microblazeel)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=microblaze ADK_TARGET_ENDIAN=little"
      cpu_arch=microblaze
      endian=el
      march=microblaze-s3adsp1800
      qemu=qemu-system-microblazeel
      qemu_machine=petalogix-s3adsp1800
      suffix=${cpu_arch}${endian}
      skipssp=microblazeel
      ;;
    microblazebe)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=microblaze ADK_TARGET_ENDIAN=big"
      cpu_arch=microblaze
      march=microblaze-s3adsp1800
      qemu=qemu-system-microblaze
      qemu_machine=petalogix-s3adsp1800
      suffix=${cpu_arch}
      skipssp=microblazebe
      ;;
    mips32)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=mips ADK_TARGET_ENDIAN=big"
      cpu_arch=mips32
      march=mips
      qemu=qemu-system-mips
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_hard
      ;;
    mips32r6)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      cpu_arch=mips32r6
      march=mips
      qemu=qemu-system-mips
      qemu_machine=malta
      qemu_args="${qemu_args} -cpu mips32r6-generic -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_hard
      ;;
    mips32sf)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      cpu_arch=mips32
      march=mips
      qemu=qemu-system-mips
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_soft
      ;;
    mips32el)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=mips ADK_TARGET_ENDIAN=little"
      cpu_arch=mips32
      endian=el
      march=mips
      qemu=qemu-system-mipsel
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_hard
      ;;
    mips32r6el)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard ADK_TARGET_CPU=mips32r6"
      cpu_arch=mips32r6
      march=mips
      qemu=qemu-system-mipsel
      qemu_machine=malta
      qemu_args="${qemu_args} -cpu mips32r6-generic -device e1000,netdev=adk0 -netdev user,id=adk0"
      endian=el
      suffix=${cpu_arch}${endian}_hard
      ;;
    mips32elsf)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft ADK_TARGET_CPU=mips32"
      cpu_arch=mips32
      endian=el
      march=mips
      qemu=qemu-system-mipsel
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_soft
      ;;
    mips64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_o32
      ;;
    mips64r6n32)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64r6"
      cpu_arch=mips64r6
      march=mips64
      qemu=qemu-system-${march}
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -cpu I6400 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_n32
      ;;
    mips64r6n64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64r6"
      cpu_arch=mips64r6
      march=mips64
      qemu=qemu-system-${march}
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -cpu I6400 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_n64
      ;;
    mips64n32)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_n32
      ;;
    mips64n64)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}_n64
      ;;
    mips64el)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      march=mips64
      endian=el
      qemu=qemu-system-mips64el
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_o32
      ;;
    mips64eln32)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      march=mips64
      endian=el
      qemu=qemu-system-mips64el
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_n32
      ;;
    mips64eln64)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64"
      cpu_arch=mips64
      march=mips64
      endian=el
      qemu=qemu-system-mips64el
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_n64
      ;;
    mips64r6eln32)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32 ADK_TARGET_CPU=mips64r6"
      cpu_arch=mips64r6
      march=mips64
      endian=el
      qemu=qemu-system-mips64el
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -cpu I6400 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_n32
      ;;
    mips64r6eln64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64r6"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64 ADK_TARGET_CPU=mips64r6"
      cpu_arch=mips64r6
      march=mips64
      endian=el
      qemu=qemu-system-mips64el
      qemu_machine=malta
      qemu_args="${qemu_args} -m 256 -cpu I6400 -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=${cpu_arch}${endian}_n64
      ;;
    mn10300)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=mn10300"
      ;;
    moxie)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=moxie"
      ;;
    msp430)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=msp430"
      ;;
    nds32le)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=nds32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=generic-nds32 ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=nds32 ADK_TARGET_ENDIAN=little"
      ;;
    nds32be)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=nds32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=generic-nds32 ADK_TARGET_ENDIAN=big"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=nds32 ADK_TARGET_ENDIAN=big"
      ;;
    nios2)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=nios2 ADK_TARGET_SYSTEM=qemu-nios2"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=nios2 ADK_TARGET_SYSTEM=qemu-nios2"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=nios2"
      qemu_machine=10m50-ghrd
      ;;
    or1k)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-or1k"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-or1k"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-or1k"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=or1k"
      qemu_machine=or1k-sim
      ;;
    ppc)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard ADK_TARGET_ENDIAN=big"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=ppc ADK_TARGET_ENDIAN=big"
      cpu_arch=ppc
      march=ppc-macppc
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      qemu_machine=mac99
      suffix=hard
      noappend=1
      ;;
    ppcsf)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      cpu_arch=ppc
      march=ppc-bamboo
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      qemu_machine=bamboo
      suffix=soft
      ;;
    ppc64)
      allowed_libc="musl glibc"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=big"
      cpu_arch=ppc64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=pseries
      suffix=${cpu_arch}
      ;;
    ppc64le)
      allowed_libc="musl glibc"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=little"
      cpu_arch=ppc64
      endian=le
      march=ppc64
      qemu=qemu-system-ppc64
      qemu_machine=pseries
      suffix=${cpu_arch}
      ;;
    riscv32)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv32"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv32"
      cpu_arch=riscv32
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      qemu_machine=virt
      ;;
    riscv32-nommu-flat)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv32 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=flat"
      cpu_arch=riscv32
      march=riscv32
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -bios none -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -cpu rv32,mmu=off"
      qemu_machine=virt
      suffix=flat_nommu
      ;;
    riscv32-nommu-elf)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv32 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv32 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=elf"
      cpu_arch=riscv32
      march=riscv32
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -bios none -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -cpu rv32,mmu=off"
      qemu_machine=virt
      suffix=elf_nommu
      ;;
    riscv64)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv64"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=riscv64"
      cpu_arch=riscv64
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      qemu_machine=virt
      ;;
    riscv64-nommu-flat)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv64 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=flat"
      cpu_arch=riscv64
      march=riscv64
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -bios none -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -cpu rv64,mmu=off"
      qemu_machine=virt
      suffix=flat_nommu
      ;;
    riscv64-nommu-elf)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=riscv64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-riscv64 ADK_TARGET_MMU=no ADK_TARGET_BINFMT=elf"
      cpu_arch=riscv64
      march=riscv64
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -bios none -m 512 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -cpu rv64,mmu=off"
      qemu_machine=virt
      suffix=elf_nommu
      ;;
    rx)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=rx"
      ;;
    s390)
      allowed_libc="musl glibc"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=s390 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-s390"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=s390 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-s390"
      cpu_arch=s390x
      qemu=qemu-system-${cpu_arch}
      qemu_machine=s390-ccw-virtio
      ;;
    sh)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=sh ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no"
      ;;
    sh2)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh2 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=little"
      cpu_arch=sh2
      ;;
    sh2eb)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh2 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=big"
      cpu_arch=sh2
      ;;
    sh3)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh3 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh3 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=little"
      cpu_arch=sh3
      ;;
    sh3eb)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh3 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=generic-sh ADK_TARGET_CPU=sh3 ADK_TARGET_MMU=no ADK_TARGET_ENDIAN=big"
      cpu_arch=sh3
      ;;
    sh4)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      cpu_arch=sh4
      march=sh
      qemu=qemu-system-sh4
      qemu_machine=r2d
      qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
      suffix=${cpu_arch}
      piggyback=0
      disk=1
      ;;
    sh4eb)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sh ADK_TARGET_FS=archive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      cpu_arch=sh4eb
      march=sh
      qemu=qemu-system-sh4eb
      qemu_machine=r2d
      qemu_args="${qemu_args} -monitor null -serial null -serial stdio -append noiotrap"
      suffix=${cpu_arch}
      piggyback=0
      disk=1
      ;;
    sparc)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sparc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-sparc"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sparc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-sparc"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=sparc"
      cpu_arch=v8
      qemu=qemu-system-sparc
      qemu_machine=SS-10
      qemu_args="${qemu_args} -m 256"
      suffix=${cpu_arch}
      ;;
    sparc-leon3)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=sparc ADK_TARGET_CPU=leon3 ADK_TARGET_SYSTEM=generic-sparc"
      cpu_arch=leon
      suffix=${cpu_arch}
      ;;
    sparc64)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test="glibc"
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sparc64 ADK_TARGET_FS=initrampiggyback ADK_TARGET_SYSTEM=qemu-sparc64"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=sparc64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-sparc64"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=sparc64"
      cpu_arch=v9
      qemu=qemu-system-sparc64
      qemu_machine=sun4u
      qemu_args="${qemu_args} -net nic,model=e1000 -net user"
      suffix=${cpu_arch}
      ;;
    tilegx)
      allowed_libc="uclibc-ng glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=toolchain ADK_TARGET_OS=$os ADK_TARGET_ARCH=tile ADK_TARGET_CPU=tilegx ADK_TARGET_SYSTEM=generic-tile"
      ;;
    v850)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=v850"
      ;;
    x86)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=x86"
      cpu_arch=i686
      qemu=qemu-system-i386
      qemu_machine=pc
      qemu_args="${qemu_args} -m 256"
      ;;
    x86_64)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86_64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86_64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86_64"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=x86_64"
      cpu_arch=x86_64
      qemu_machine=pc
      qemu_args="${qemu_args} -m 256"
      libdir=lib64
      ;;
    x86_64_x32)
      allowed_libc="musl glibc"
      runtime_test="musl glibc"
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86_64 ADK_TARGET_ABI=x32"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-x86_64 ADK_TARGET_ABI=x32"
      cpu_arch=x86_64
      march=x86_64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=pc
      libdir=libx32
      suffix=x32
      ;;
    xtensa)
      allowed_libc="newlib uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=xtensa ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-xtensa ADK_TARGET_CPU=dc233c ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=toolchain ADK_TARGET_OS=baremetal ADK_TARGET_ARCH=xtensa"
      cpu_arch=dc233c
      qemu=qemu-system-xtensa
      qemu_machine=kc705
      qemu_args="${qemu_args} -cpu dc233c -m 256"
      suffix=${cpu_arch}
      ;;
    xtensabe)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=xtensa ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-xtensa ADK_TARGET_CPU=kc705_be ADK_TARGET_ENDIAN=big"
      cpu_arch=dc233c
      qemu=qemu-system-xtensa
      qemu_machine=kc705
      qemu_args="${qemu_args} -cpu dc233c"
      suffix=${cpu_arch}
      ;;
    xtensa-nommu)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_OS=$os ADK_TARGET_ARCH=xtensa ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-xtensa ADK_TARGET_CPU=de212 ADK_TARGET_ENDIAN=little ADK_TARGET_MMU=no"
      cpu_arch=de212
      march=xtensa
      qemu=qemu-system-xtensa
      qemu_machine=kc705-nommu
      qemu_args="${qemu_args} -cpu de212 -m 256"
      suffix=${cpu_arch}_flat_nommu
      ;;
    *)
      echo "architecture ${arch} not supported"; exit 1;;
  esac
}

# creating test script to be run on boot
create_run_sh() {
  test=$1
  file=$2
  type=$3

  if [ "$type" = "netcat" ]; then
    tee="| tee -a /REPORT"
  fi

cat > $file << EOF
#!/bin/sh
uname -a
mount -o remount,rw /
if [ -x /usr/sbin/rdate ]; then
  if [ \$ntpserver ]; then
    rdate \$ntpserver
  else
    rdate time.fu-berlin.de
  fi
fi
EOF
  if [ "$type" = "netcat" ]; then
cat >> $file << EOF
dmesg >> /REPORT
EOF
  fi
  # boot test
  if [ $test = "boot" ]; then
cat >> $file << EOF
if [ -x /usr/bin/size ]; then
  size /bin/busybox $tee
else
  ls -la /bin/busybox $tee
fi
helloworld
helloworld.static
if [ -x helloworld-cxx ]; then
helloworld-cxx
fi
if [ -x helloworld-cxx.static ]; then
helloworld-cxx.static
fi
EOF
  if [ $static -eq 0 ]; then
cat >> $file << EOF
for i in \$(ls /lib/* 2>/dev/null);do
  if [ -x /usr/bin/size ]; then
    size \$i $tee
  else
    ls -la \$i $tee
  fi
done
EOF
  fi
  fi
  # ltp test
  if [ $test = "ltp" ]; then
cat >> $file << EOF
/opt/ltp/runltp $tee
EOF
  fi
  # native test
  if [ $test = "native" ]; then
cat >> $file << EOF
echo '#include <stdio.h>\nint main() {\n printf("Hello World");\n return 0; \n}'> /hello.c
gcc -o /hello /hello.c $tee
/hello $tee
if [ \$? -eq 0 ]; then
  echo "\nsuccess"
else
  echo "\nfailed"
fi
EOF
  fi
  # mksh test
  if [ $test = "mksh" ]; then
cat >> $file << EOF
tty=\$(cat /proc/consoles |cut -f 1 -d " ")
mksh -T !/dev/\$tty -c '/opt/mksh/test.sh' $tee
EOF
  fi
  # libc test
  if [ $test = "libc" ]; then
cat >> $file << EOF
cd /usr/lib/uclibc-ng-test/test
sh ./uclibcng-testrunner.sh $tee
EOF
  fi
  # info
cat >> $file <<EOF
if [ -f /etc/.adkgithash ]; then
  echo "OpenADK git version:"
  cat /etc/.adkgithash
fi
if [ -f /etc/.adkcompiler ]; then
  echo "Compiler used:"
  cat /etc/.adkcompiler
fi
if [ -f /etc/.adklinker ]; then
  echo "Linker used:"
  cat /etc/.adklinker
fi
EOF

  if [ "$type" = "netcat" ]; then
cat >> $file << EOF
echo quit|nc $buildserver 9999
EOF
  fi

  if [ "$type" = "quit" ]; then
cat >> $file << EOF
exit
EOF
  fi
  chmod u+x $file
}

runtest() {
  lib=$1
  arch=$2
  test=$3

  if [ $ntp ]; then
    qemu_append="-append ntpserver=$ntp"
  fi
  if [ $shell -eq 1 ]; then
    qemu_append="-append shell"
  fi

  qemu=qemu-system-${arch}
  march=${arch}
  get_arch_info $arch $lib

  case $emulator in
    qemu)
      echo "Using QEMU as emulator"
      if ! which $qemu >/dev/null; then
        echo "Checking if $qemu is installed... failed"
        exit 1
      fi
      qemuver=$(${qemu} -version|awk '{ print $4 }'|head -1)
      if [ "$arch" != "metag" ]; then
        if [ $(echo $qemuver |sed -e "s#\.##g" -e "s#,##") -lt 240 ]; then
          echo "Your qemu version is too old. Please update to 2.4 or greater"
          exit 1
        fi
      fi
      ;;
    gdb)
      echo "Using GDB as simulator"
      ;;
    *)
      echo "emulator/simulator not supported"
      exit 1
      ;;
  esac

  echo "Starting test for $lib and $arch"
  # check if initramfs, piggyback or disk is used
  if [ $piggyback -eq 1 ]; then
    echo "Using extra directory for test image creation"
    root=openadk/extra
    rm -rf openadk/extra 2>/dev/null
    mkdir openadk/extra 2>/dev/null
    if [ ! -z $suffix ]; then
        kernel=openadk/firmware/${emulator}-${march}_${lib}_${suffix}/${emulator}-${march}-initramfspiggyback-kernel
    else
      kernel=openadk/firmware/${emulator}-${march}_${lib}/${emulator}-${march}-initramfspiggyback-kernel
    fi
  elif [ $disk -eq 1 ]; then
    echo "Using disk image for test"
    if [ ! -z $suffix ]; then
        kernel=openadk/firmware/${emulator}-${march}_${lib}_${suffix}/${emulator}-${march}-archive-kernel
    else
      kernel=openadk/firmware/${emulator}-${march}_${lib}/${emulator}-${march}-archive-kernel
    fi
  else
    echo "Generating root filesystem for test run"
    root=$(mktemp -d /tmp/XXXX)
    if [ ! -z $suffix ]; then
      archive=openadk/firmware/${emulator}-${march}_${lib}_${suffix}/qemu-${march}-${lib}-initramfsarchive.tar.gz
      kernel=openadk/firmware/${emulator}-${march}_${lib}_${suffix}/qemu-${march}-initramfsarchive-kernel
    else
      archive=openadk/firmware/${emulator}-${march}_${lib}/${emulator}-${march}-${lib}-initramfsarchive.tar.gz
      kernel=openadk/firmware/${emulator}-${march}_${lib}/${emulator}-${march}-initramfsarchive-kernel
    fi

    if [ ! -f $archive ]; then
      echo "No root filesystem available for architecture ${arch} tried $archive"
      exit 1
    fi
    tar -xf $archive -C $root
  fi

  create_run_sh $test ${root}/run.sh quit

  if [ $piggyback -eq 1 ]; then
    (cd openadk && make v)
  elif [ $disk -eq 1 ]; then
    (cd openadk && ./scripts/create.sh -i 256 qemu-${march}.img firmware/${emulator}-${march}_${lib}_${cpu_arch}/${emulator}-${march}-${libc}-archive+kernel.tar.gz)
  else
    echo "Creating initramfs filesystem"
    (cd $root; find . | cpio -o -C512 -Hnewc |gzip -c > ${topdir}/initramfs.${arch})
    rm -rf $root
    qemu_args="$qemu_args -initrd initramfs.${arch}"
  fi

  # qemu-ppc overwrites existing commandline
  if [ $noappend -eq 0 ]; then
    qemu_args="$qemu_args ${qemu_append}"
  fi

  report=REPORT.${arch}.${test}.${libver}${rsuffix}

  echo "Now running the test ${test} in ${emulator} for architecture ${arch} and ${lib}"
  case $emulator in
    qemu)
      if [ $disk -eq 1 ]; then
        echo "${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot openadk/qemu-${march}.img"
        ${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot openadk/qemu-${march}.img | tee $report
      else
        echo "${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot"
        ${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot | tee $report
      fi
      ;;
    gdb)
      echo "$emulator ${arch} ${kernel}"
      ./openadk/toolchain_${emulator}-${march}_${lib}_${model}_${binfmt}/usr/bin/${gdbcmd} ${kernel}
      ;;
  esac
  if [ $? -eq 0 ]; then
    echo "Test ${test} for ${arch} finished. See $report"
  else
    echo "Test ${test} failed for ${arch} with ${lib} ${libver}."
  fi
}

build() {
  lib=$1
  arch=$2
  test=$3
  system=$4
  rootfs=$5

  DEFAULT=
  cd openadk

  if [[ $targetmode ]]; then
    DEFAULT="ADK_APPLIANCE=test ADK_TARGET_ARCH=$arch ADK_TARGET_SYSTEM=$system ADK_TARGET_FS=$rootfs"
  else
    get_arch_info $arch $lib
  fi

  if [ $verbose -eq 1 ]; then
    DEFAULT="$DEFAULT ADK_VERBOSE=1"
  fi

  # build defaults for different tests
  if [ $test = "toolchain" ]; then
    DEFAULT="$DEFAULT ADK_TEST_TOOLCHAIN=y"
  fi
  if [ $test = "boot" ]; then
    DEFAULT="$DEFAULT ADK_TEST_BASE=y"
  fi
  if [ $test = "ltp" ]; then
    DEFAULT="$DEFAULT ADK_TEST_LTP=y"
  fi
  if [ $test = "mksh" ]; then
    DEFAULT="$DEFAULT ADK_TEST_MKSH=y"
    REBUILD=.rebuild.mksh
  fi
  if [ $test = "libc" ]; then
    DEFAULT="$DEFAULT ADK_TEST_UCLIBC_NG_TEST=y"
  fi
  if [ $test = "native" ]; then
    case $lib in
      uclibc-ng)
        DEFAULT="$DEFAULT ADK_TEST_UCLIBC_NG_NATIVE=y"
        ;;
      musl)
        DEFAULT="$DEFAULT ADK_TEST_MUSL_NATIVE=y"
        ;;
      glibc)
        DEFAULT="$DEFAULT ADK_TEST_GLIBC_NATIVE=y"
        ;;
    esac
  fi

  # build defaults for different C library
  DEFAULT="$DEFAULT ADK_TARGET_LIBC=$lib"
  case $lib in
    uclibc-ng)
      DEFAULT="$DEFAULT $default_uclibc_ng"
      ;;
    musl)
      DEFAULT="$DEFAULT $default_musl"
      ;;
    glibc)
      DEFAULT="$DEFAULT $default_glibc"
      ;;
    newlib)
      DEFAULT="$DEFAULT $default_newlib"
      ;;
  esac
  # use special C library version
  if [[ $libcversion ]]; then
    DEFAULT="$DEFAULT ADK_TARGET_LIBC_VERSION=$libcversion"
  fi
  # use special Linux kernel version
  if [[ $kernelversion ]]; then
    DEFAULT="$DEFAULT ADK_TARGET_KERNEL_VERSION=$kernelversion"
  fi
  if [[ $binutilsversion ]]; then
    DEFAULT="$DEFAULT ADK_TOOLCHAIN_BINUTILS_VERSION=$binutilsversion"
  fi
  if [[ $gccversion ]]; then
    DEFAULT="$DEFAULT ADK_TOOLCHAIN_GCC_VERSION=$gccversion"
  fi
  if [[ $gdbversion ]]; then
    DEFAULT="$DEFAULT ADK_TOOLCHAIN_GDB_VERSION=$gdbversion"
  fi

  rm .config* .defconfig 2>/dev/null
  echo "Using following defaults: $DEFAULT"
  make $DEFAULT defconfig

  if [ $create -eq 1 ]; then
    printf "ADK_CREATE_TOOLCHAIN_ARCHIVE=y\n" >> .config
  fi
  if [ $static -eq 1 ]; then
    printf "ADK_TARGET_USE_STATIC_LIBS_ONLY=y\n" >> .config
  fi
  if [ $cxx -eq 1 ]; then
    if [ "$arch" = "$skipcxx" -o "$lib" = "newlib" ]; then
      echo "Skipping $skipcxx"
    else
      printf "ADK_TOOLCHAIN_WITH_CXX=y\n" >> .config
      printf "ADK_COMPILE_LIBSTDCXX=y\n" >> .config
      printf "ADK_PACKAGE_LIBSTDCXX=y\n" >> .config
    fi
  fi
  if [ $ssp -eq 1 ]; then
    printf "ADK_TARGET_USE_SSP=y\n" >> .config
  fi
  if [ $debug -eq 1 ]; then
    printf "ADK_DEBUG=y\n" >> .config
  fi
  if [ ! -z $threads ]; then
    if [ $threads = "none" ]; then
      printf "ADK_TARGET_WITHOUT_THREADS=y\n" >> .config
    fi
    if [ $threads = "lt" ]; then
      printf "ADK_TARGET_WITH_LT=y\n" >> .config
    fi
    if [ $threads = "nptl" ]; then
      printf "ADK_TARGET_WITH_NPTL=y\n" >> .config
    fi
  fi

  for pkg in $packages; do
    p=$(echo $pkg|tr '[:lower:]' '[:upper:]'|tr - _);printf "ADK_COMPILE_$p=y\nADK_PACKAGE_$p=y\n" >> .config
  done

  # refresh after any changes to config
  yes|make oldconfig >/dev/null

  if [ $clean -eq 1 ]; then
    echo "cleaning openadk build directory"
    make cleansystem
  fi
  if [ ! -z $REBUILD ]; then
    touch $REBUILD
  fi
  make $DEFAULT all
  if [ $? -ne 0 ];then
    echo "build failed"
    exit 1
  fi
  cd ..
}	

for lib in ${libc}; do
  case $lib in
    uclibc-ng)
      archlist=$arch_list_uclibcng
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=1.0.47
      fi
      libver=uClibc-ng-${version}
      libdir=uClibc-ng
      ;;
    glibc)
      archlist=$arch_list_glibc
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=2.39
      fi
      libver=glibc-${version}
      libdir=glibc
      ;;
    musl)
      archlist=$arch_list_musl
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=1.2.5
      fi
      libver=musl-${version}
      libdir=musl
      ;;
    newlib)
      archlist=$arch_list_newlib
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=4.4.0
      fi
      libver=newlib-${version}
      libdir=newlib
      ;;
    *)
      echo "$lib not supported"
      exit 1
      ;;
  esac
  if [ ! -z $archs ]; then
    archlist="$archs"
  fi
  # libc source used?
  if [ ! -z $libcsource ]; then
    if [ ! -d $libcsource ]; then
      echo "Not a directory."
      exit 1
    fi
    if [ ! -f openadk/dl/${libver}.tar.gz ]; then
	usrc=$(mktemp -d /tmp/XXXX)
	echo "Creating C library source tarball openadk/dl/${libver}.tar.gz"
	cp -a $libcsource $usrc/$libver
	mkdir -p $topdir/openadk/dl 2>/dev/null
	rm $topdir/openadk/dl/${libver}.tar.gz 2>/dev/null
	(cd $usrc && tar czf $topdir/openadk/dl/${libver}.tar.gz ${libver} && rm -rf $usrc)
	touch $topdir/openadk/dl/${libver}.tar.gz.nohash
	# we need to clean system, when external source is used
	if [ $noclean -eq 0 ]; then
	    clean=1
	fi
    else
      echo "Libc ${libver} tarball already exists, skipping creation"
    fi
  fi
  # binutils source used?
  if [ ! -z $binutilssource ]; then
    if [ ! -d $binutilssource ]; then
      echo "Not a directory."
      exit 1
    fi
    if [ ! -f openadk/dl/binutils-git.tar.gz ]; then
	usrc=$(mktemp -d /tmp/XXXX)
	echo "Creating binutils source tarball openadk/dl/binutils-git.tar.gz"
	(cd $binutilssource && ./src-release.sh binutils)
	tar xf $binutilssource/binutils-*.tar -C $usrc
	(cd $usrc && mv binutils-* binutils-git)
	mkdir -p $topdir/openadk/dl 2>/dev/null
	rm $topdir/openadk/dl/binutils-git.tar.gz 2>/dev/null
	(cd $usrc && tar czf $topdir/openadk/dl/binutils-git.tar.gz binutils-git && rm -rf $usrc)
	touch $topdir/openadk/dl/binutils-git.tar.gz.nohash
	# we need to clean system, when external source is used
	if [ $noclean -eq 0 ]; then
	    clean=1
	fi
    else
      echo "Binutils tarball already exists, skipping creation"
    fi
  fi
  # gcc source used?
  if [ ! -z $gccsource ]; then
    if [ ! -d $gccsource ]; then
      echo "Not a directory."
      exit 1
    fi
    if [ ! -f openadk/dl/gcc-git.tar.gz ]; then
	usrc=$(mktemp -d /tmp/XXXX)
	echo "Creating gcc source tarball openadk/dl/gcc-git.tar.gz"
	cp -a $gccsource $usrc/gcc-git
	mkdir -p $topdir/openadk/dl 2>/dev/null
	rm $topdir/openadk/dl/gcc-git.tar.gz 2>/dev/null
	(cd $usrc && tar czf $topdir/openadk/dl/gcc-git.tar.gz gcc-git && rm -rf $usrc)
	touch $topdir/openadk/dl/gcc-git.tar.gz.nohash
	# we need to clean system, when external source is used
	if [ $noclean -eq 0 ]; then
	    clean=1
	fi
    else
      echo "GCC tarball already exists, skipping creation"
    fi
  fi
  # gdb source used?
  if [ ! -z $gdbsource ]; then
    if [ ! -d $gdbsource ]; then
      echo "Not a directory."
      exit 1
    fi
    if [ ! -f openadk/dl/gdb-git.tar.gz ]; then
	usrc=$(mktemp -d /tmp/XXXX)
	echo "Creating gdb source tarball openadk/dl/gdb-git.tar.gz"
	cp -a $gdbsource $usrc/gdb-git
	mkdir -p $topdir/openadk/dl 2>/dev/null
	rm $topdir/openadk/dl/gdb-git.tar.gz 2>/dev/null
	(cd $usrc && tar czf $topdir/openadk/dl/gdb-git.tar.gz gdb-git && rm -rf $usrc)
	touch $topdir/openadk/dl/gdb-git.tar.gz.nohash
	# we need to clean system, when external source is used
	if [ $noclean -eq 0 ]; then
	    clean=1
	fi
    else
      echo "GDB tarball already exists, skipping creation"
    fi
  fi
  # Linux kernel source used?
  if [ ! -z $kernelsource ]; then
    if [ ! -d $kernelsource ]; then
      echo "Not a directory."
      exit 1
    fi
    if [ ! -f openadk/dl/linux-git.tar.gz ]; then
      usrc=$(mktemp -d /tmp/XXXX)
      echo "Creating Linux kernel source tarball openadk/dl/linux-git.tar.gz"
      cp -a $kernelsource $usrc/linux-git
      mkdir -p $topdir/openadk/dl 2>/dev/null
      rm $topdir/openadk/dl/linux-git.tar.gz 2>/dev/null
      (cd $usrc && tar czf $topdir/openadk/dl/linux-git.tar.gz linux-git && rm -rf $usrc)
      touch $topdir/openadk/dl/linux-git.tar.gz.nohash
      # we need to clean system, when external source is used
      if [ $noclean -eq 0 ]; then
        clean=1
      fi
    else
      echo "Tarball already exists, skipping creation"
    fi
  fi
  # start with a clean dir
  if [ $cleandir -eq 1 ]; then
    echo "completely cleaning openadk build directory"
    (cd openadk && make cleandir)
  fi

  if [[ $targetmode ]]; then
    create_run_sh $test run.sh netcat

    while read -u3 line; do
      target_host=$(echo $line|cut -f 1 -d ,)
      target_ip=$(echo $line|cut -f 2 -d ,)
      target_arch=$(echo $line|cut -f 3 -d ,)
      target_system=$(echo $line|cut -f 4 -d ,)
      target_suffix=$(echo $line|cut -f 5 -d ,)
      target_rootfs=$(echo $line|cut -f 6 -d ,)
      target_powerid=$(echo $line|cut -f 7 -d ,)
      echo "Testing target system $target_system ($target_arch) with $target_rootfs on $target_host"
      build $lib $target_arch $test $target_system $target_rootfs
      kernel=openadk/firmware/${target_system}_${lib}_${target_suffix}/${target_system}-${target_rootfs}-kernel
      tarball=openadk/firmware/${target_system}_${lib}_${target_suffix}/${target_system}-${lib}-${target_rootfs}.tar.gz
      scp $kernel root@${bootserver}:/tftpboot/${target_host}
      ssh -n root@${bootserver} "cd /tftpboot; ln -sf ${target_host} vmlinux"
      ssh -n root@${bootserver} "mkdir /nfsroot/${target_host} 2>/dev/null"
      gunzip $tarball | ssh root@${bootserver} "tar -xf - -C /nfsroot/${target_host}"
      scp run.sh root@${bootserver}:/nfsroot/${target_host}
      echo "Powering on target system"
      ssh -n root@${bootserver} "sispmctl -o $target_powerid"
      echo "Waiting for target system to finish"
      nc -l -p 9999
      echo "Test finished. Powering off target system"
      ssh -n root@${bootserver} "sispmctl -f $target_powerid"
      scp root@${bootserver}:/nfsroot/${target_host}/REPORT REPORT.${target_arch}.${target_system}.${test}.${libver}
      ssh -n root@${bootserver} "rm /nfsroot/${target_host}/REPORT"
    done 3< $targets
  else
    for arch in $archlist; do
      get_arch_info $arch $lib
      report=REPORT.${arch}.${test}.${libver}${rsuffix}
      if [ $cont -eq 1 ]; then
        if [ -f $report ]; then
          echo "Skipping already run test $test for $arch and $lib"
          continue
        fi
      fi
      if [ "$arch" = "$skiparchs" ]; then
        echo "Skipping $skiparchs"
        continue
      fi
      if [ "$threads" = "lt" ]; then
        if [ "$arch" = "$skiplt" ]; then
          echo "Skipping $skiplt"
          continue
        fi
      fi
      if [ $static -eq 1 ]; then
        if [ "$arch" = "$skipstatic" ]; then
          echo "Skipping $skipstatic"
          continue
        fi
      fi
      if [ $ssp -eq 1 ]; then
        if [ "$arch" = "$skipssp" ]; then
          echo "Skipping $skipssp"
          continue
        fi
      fi
      if [[ "$allowed_tests" = *${test}* ]]; then
        if [[ "$allowed_libc" = *${lib}* ]]; then
          echo "Compiling for $lib and $arch testing $test"
          build $lib $arch $test
          if [ "$test" != "toolchain" ]; then
            if [[ "$runtime_test" = *${lib}* ]]; then
              runtest $lib $arch $test
            fi
          else
            # fake stamp for continue
            touch $report
          fi
        else
          echo "$lib not available for $arch"
        fi
      else
         echo "$test not available for $arch and $lib"
      fi
    done
  fi
done
echo "All tests finished."
exit 0
