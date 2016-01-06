#!/usr/bin/env mksh
#
# Copyright © 2014-2015
#	Waldemar Brodkorb <wbx@embedded-test.org>
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
arch_list_uclibcng="alpha armv5 armv7 armeb arcv1 arcv2 arcv1-be arcv2-be avr32 bfin c6x crisv10 crisv32 ia64 lm32 m68k m68k-nommu metag microblazeel microblazebe mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64el mips64eln64 or1k ppc ppcsf sh3 sh4 sh4eb sparc x86 x86_64 xtensa"

# musl
arch_list_musl="aarch64 armv5 armv7 armeb microblazeel microblazebe mips mipssf mipsel mipselsf or1k ppc sh4 sh4eb x86 x86_64"

# glibc
arch_list_glibc="aarch64 alpha armv5 armv7 armeb ia64 microblazeel microblazebe mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 nios2 ppc ppcsf ppc64 s390 sh4 sh4eb sparc sparc64 tile x86 x86_64"

# newlib
arch_list_newlib="armv5 armeb bfin crisv10 crisv32 frv lm32 m68k microblazeel mips mipsel or1k ppc sparc x86"

topdir=$(pwd)
giturl=http://git.openadk.org/openadk.git
valid_libc="uclibc-ng musl glibc newlib"
valid_tests="toolchain boot libc ltp mksh native"

bootserver=10.0.0.1
buildserver=10.0.0.2

tools='make git wget xz cpio tar awk sed'
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
Syntax: $0 [ --libc=<libc> --arch=<arch> --test=<test> ]

Explanation:
	--libc=<libc>                C library to use (${valid_libc})
	--arch=<arch>                architecture to check (otherwise all supported)
	--skiparch=<arch>            architectures to skip when all choosen
	--targets=<targets.txt>      a list of remote targets to test via nfsroot or chroot
	--test=<test>                run test (${valid_tests}), default toolchain
	--libc-source=<dir>          use directory with source for C library
	--gcc-source=<dir>           use directory with source for gcc
	--binutils-source=<dir>      use directory with source for binutils
	--gdb-source=<dir>           use directory with source for gdb
	--libc-version=<version>     use version of C library
	--gcc-version=<version>      use version of gcc
	--binutils-version=<version> use version of binutils
	--gdb-version=<version>      use version of gdb 
	--ntp=<ntpserver>            set NTP server for test run
	--packages=<packagelist>     add extra packages to the build
	--update                     update OpenADK source via git pull, before building
	--continue                   continue on a broken build
	--cleandir                   clean OpenADK build directories before build
	--clean                      clean OpenADK build directory for single arch
	--no-clean                   do not clean OpenADK build directory for single arch
	--debug                      enable debug output from OpenADK
	--shell                      start a shell instead of test autorun
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
debug=0
ntp=""
libc=""
test="toolchain"

while [[ $1 != -- && $1 = -* ]]; do case $1 { 
  (--cleandir) cleandir=1; shift ;;
  (--clean) clean=1; shift ;;
  (--no-clean) noclean=1; shift ;;
  (--debug) debug=1; shift ;;
  (--update) update=1; shift ;;
  (--continue) cont=1; shift ;;
  (--shell) shell=1 shift ;;
  (--libc=*) libc=${1#*=}; shift ;;
  (--arch=*) archs=${1#*=}; shift ;;
  (--skiparch=*) skiparchs=${1#*=}; shift ;;
  (--targets=*) targets=${1#*=}; shift ;;
  (--test=*) test=${1#*=}; shift ;;
  (--libc-source=*) libcsource=${1#*=}; shift ;;
  (--gcc-source=*) gccsource=${1#*=}; shift ;;
  (--binutils-source=*) binutilssource=${1#*=}; shift ;;
  (--gdb-source=*) gdbsource=${1#*=}; shift ;;
  (--libc-version=*) libcversion=${1#*=}; shift ;;
  (--gcc-version=*) gccversion=${1#*=}; shift ;;
  (--binutils-version=*) binutilsversion=${1#*=}; shift ;;
  (--gdb-version=*) gdbversion=${1#*=}; shift ;;
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
  noappend=0
  piggyback=0
  suffix=
  allowed_libc=
  runtime_test=
  qemu_args=-nographic

  case ${arch} in
    aarch64)
      allowed_libc="musl glibc"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-aarch64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-aarch64"
      cpu_arch=aarch64
      qemu_machine=virt
      qemu_args="${qemu_args} -cpu cortex-a57 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
      ;;
    alpha)
      allowed_libc="uclibc-ng glibc"
      runtime_test="glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=alpha ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-alpha"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=alpha ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-alpha"
      cpu_arch=alpha
      march=alpha
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -monitor null"
      ;;
    armv5)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=arm ADK_TARGET_ENDIAN=little ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_CPU=arm926ej-s"
      cpu_arch=arm
      march=arm-versatilepb
      qemu=qemu-system-${cpu_arch}
      qemu_machine=versatilepb
      suffix=soft_eabi
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
      qemu_args="${qemu_args} -cpu arm926 -net user -net nic,model=smc91c111"
      ;;
    armv7)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9"
      cpu_arch=arm
      march=arm-vexpress-a9
      qemu=qemu-system-${cpu_arch}
      qemu_machine=vexpress-a9
      suffix=hard_eabihf
      dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
      qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
      ;;
    armeb)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=arm ADK_TARGET_ENDIAN=big ADK_TARGET_SYSTEM=toolchain-arm"
      ;;
    arcv1)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv1 ADK_TARGET_ENDIAN=little"
      emulator=nsim
      cpu_arch=arc
      piggyback=1
      ;;
    arcv2)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv2 ADK_TARGET_ENDIAN=little"
      emulator=nsim
      cpu_arch=arc
      piggyback=1
      ;;
    arcv1-be)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv1 ADK_TARGET_ENDIAN=big"
      emulator=nsim
      cpu_arch=arceb
      march=arcv1
      piggyback=1
      ;;
    arcv2-be)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc ltp mksh native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv2 ADK_TARGET_ENDIAN=big"
      emulator=nsim
      cpu_arch=arceb
      march=arcv2
      piggyback=1
      ;;
    avr32)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=avr32 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-avr32"
      ;;
    bfin)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=bfin ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-bfin"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=bfin ADK_TARGET_SYSTEM=toolchain-bfin"
      ;;
    c6x)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=c6x ADK_TARGET_SYSTEM=toolchain-c6x"
      ;;
    crisv10)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv10"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv10"
      ;;
    crisv32)
      allowed_libc="uclibc-ng newlib"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-cris"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_ENDIAN=little ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv32"
      cpu_arch=crisv32
      march=cris
      qemu=qemu-system-${march}
      qemu_machine=axis-dev88
      piggyback=1
      ;;
    frv)
      allowed_libc="newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=frv ADK_TARGET_SYSTEM=toolchain-frv"
      ;;
    ia64)
      allowed_libc="glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_glibbc="ADK_APPLIANCE=new ADK_TARGET_ARCH=ia64 ADK_TARGET_SYSTEM=toolchain-ia64"
      ;;
    h8300)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=h8300 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-h8300"
      ;;
    lm32)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=lm32 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-lm32"
      ;;
    m68k)
      allowed_libc="uclibc-ng newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-m68k-q800"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=m68k ADK_TARGET_SYSTEM=toolchain-m68k ADK_TARGET_CPU=68040"
      ;;
    m68k-nommu)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-m68k-mcf5208"
      ;;
    metag)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=metag ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-metag"
      cpu_arch=metag
      qemu=qemu-system-meta
      qemu_args="-nographic -display none -device da,exit_threads=1 -chardev stdio,id=chan1 -chardev pty,id=chan2"
      qemu_machine=01sp
      piggyback=1
      ;;
    microblazeel)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=microblaze ADK_TARGET_SYSTEM=toolchain-microblaze ADK_TARGET_ENDIAN=little"
      cpu_arch=microblazeel
      march=microblaze-s3adsp1800
      qemu_machine=petalogix-s3adsp1800
      ;;
    microblazebe)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-s3adsp1800 ADK_TARGET_ENDIAN=big"
      cpu_arch=microblaze
      march=microblaze-s3adsp1800
      qemu=qemu-system-${cpu_arch}
      qemu_machine=petalogix-s3adsp1800
      ;;
    mips)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=toolchain-mips ADK_TARGET_ENDIAN=big"
      cpu_arch=mips
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=hard
      ;;
    mipssf)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft"
      cpu_arch=mips
      march=mips
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=soft
      ;;
    mipsel)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=toolchain-mips ADK_TARGET_ENDIAN=little"
      cpu_arch=mipsel
      march=mips
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=hard
      ;;
    mipselsf)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
      cpu_arch=mipsel
      march=mips
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=soft
      ;;
    mips64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32"
      cpu_arch=mips64
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=o32
      ;;
    mips64n32)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32"
      cpu_arch=mips64
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=n32
      ;;
    mips64n64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64"
      cpu_arch=mips64
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=n64
      ;;
    mips64el)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32"
      cpu_arch=mips64el
      march=mips64
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=o32
      ;;
    mips64eln32)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32"
      cpu_arch=mips64el
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=n32
      ;;
    mips64eln64)
      allowed_libc="uclibc-ng glibc"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64"
      cpu_arch=mips64el
      march=mips64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=malta
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      suffix=n64
      ;;
    ppcsf)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft"
      cpu_arch=ppc
      march=ppc-bamboo
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      qemu_machine=bamboo
      suffix=soft
      ;;
    nios2)
      allowed_libc="glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=new ADK_TARGET_ARCH=nios2 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-nios2"
      ;;
    or1k)
      allowed_libc="uclibc-ng musl newlib"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-or1k"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-or1k"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=or1k ADK_TARGET_SYSTEM=toolchain-or1k"
      ;;
    ppc)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=ppc ADK_TARGET_SYSTEM=toolchain-ppc"
      cpu_arch=ppc
      march=ppc-macppc
      qemu=qemu-system-${cpu_arch}
      qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
      qemu_machine=mac99
      suffix=hard
      noappend=1
      ;;
    ppc64)
      allowed_libc="glibc"
      runtime_test="glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=big"
      cpu_arch=ppc64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=pseries
      ;;
    s390)
      allowed_libc="glibc"
      runtime_test="glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=s390 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-s390"
      cpu_arch=s390x
      qemu=qemu-system-${cpu_arch}
      qemu_machine=s390-ccw-virtio-2.4
      ;;
    sh2)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=toolchain-sh ADK_TARGET_CPU=sh2"
      cpu_arch=sh2
      ;;
    sh3)
      allowed_libc="uclibc-ng"
      runtime_test=""
      allowed_tests="toolchain"
      default_uclibc_ng="ADK_APPLIANCE=new ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=toolchain-sh ADK_TARGET_CPU=sh3"
      cpu_arch=sh3
      ;;
    sh4)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=toolchain-sh ADK_TARGET_CPU=sh4"
      cpu_arch=sh4
      march=sh
      qemu=qemu-system-${cpu_arch}
      qemu_machine=r2d
      qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
      ;;
    sh4eb)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test=""
      allowed_tests="toolchain"
      cpu_arch=sh4eb
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
      march=sh
      qemu=qemu-system-${cpu_arch}
      qemu_machine=r2d
      qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
      ;;
    sparc)
      allowed_libc="uclibc-ng glibc newlib"
      runtime_test="uclibc-ng glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=sparc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sparc"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=sparc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sparc"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=sparc ADK_TARGET_SYSTEM=toolchain-sparc"
      cpu_arch=sparc
      qemu_machine=SS-5
      ;;
    sparc64)
      allowed_libc="glibc"
      runtime_test="glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=sparc64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sparc64"
      cpu_arch=sparc64
      qemu_machine=sun4u
      qemu_args="${qemu_args} -net nic,model=e1000 -net user"
      ;;
    tile)
      allowed_libc="glibc"
      runtime_test=""
      allowed_tests="toolchain"
      default_glibc="ADK_APPLIANCE=new ADK_TARGET_ARCH=tile ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-tile"
      ;;
    x86)
      allowed_libc="uclibc-ng musl glibc newlib"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86"
      default_newlib="ADK_APPLIANCE=new ADK_TARGET_ARCH=x86 ADK_TARGET_SYSTEM=toolchain-x86"
      cpu_arch=i686
      qemu=qemu-system-i386
      qemu_machine=pc
      qemu_args="${qemu_args}"
      ;;
    x86_64)
      allowed_libc="uclibc-ng musl glibc"
      runtime_test="uclibc-ng musl glibc"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86_64"
      default_glibc="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86_64"
      default_musl="ADK_APPLIANCE=test ADK_TARGET_ARCH=x86_64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-x86_64"
      cpu_arch=x86_64
      qemu_machine=pc
      libdir=lib64
      ;;
    x86_64_x32)
      allowed_libc="musl glibc"
      runtime_test=""
      allowed_tests="toolchain"
      cpu_arch=x86_64
      qemu=qemu-system-${cpu_arch}
      qemu_machine=pc
      libdir=libx32
      ;;
    xtensa)
      allowed_libc="uclibc-ng"
      runtime_test="uclibc-ng"
      allowed_tests="toolchain boot libc mksh ltp native"
      default_uclibc_ng="ADK_APPLIANCE=test ADK_TARGET_ARCH=xtensa ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-xtensa"
      cpu_arch=xtensa
      qemu=qemu-system-${cpu_arch}
      qemu_machine=ml605
      qemu_args="${qemu_args} -cpu dc233c"
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
if [ \$ntpserver ]; then
  rdate \$ntpserver
else
  rdate time.fu-berlin.de
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
file /bin/busybox $tee
size /bin/busybox $tee
for i in \$(ls /lib/*.so|grep -v libgcc);do
  size \$i $tee
done
EOF
  fi
  # ltp test
  if [ $test = "ltp" ]; then
cat >> $file << EOF
/opt/ltp/runltp $tee
EOF
  fi
  # mksh test
  if [ $test = "mksh" ]; then
cat >> $file << EOF
mksh /opt/mksh/test.sh $tee
EOF
  fi
  # libc test
  if [ $test = "libc" ]; then
    case $lib in
      uclibc-ng)
cat >> $file << EOF
cd /opt/uclibc-ng/test
sh ./uclibcng-testrunner.sh $tee
EOF
      ;;
      musl|glibc)
cat >> $file << EOF
cd /opt/libc-test
CC=: make run $tee
EOF
      ;;
    esac
  fi

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
      qemuver=$(${qemu} -version|awk '{ print $4 }')
      if [ "$arch" != "metag" ]; then
        if [ $(echo $qemuver |sed -e "s#\.##g" -e "s#,##") -lt 240 ]; then
          echo "Your qemu version is too old. Please update to 2.4 or greater"
          exit 1
        fi
      fi
      ;;
    nsim)
      echo "Using Synopsys NSIM as simulator"
      if ! which nsimdrv >/dev/null; then
        echo "Checking if $emulator is installed... failed"
        exit 1
      fi
      ;;
    *)
      echo "emulator/simulator not supported"
      exit 1
      ;;
  esac

  echo "Starting test for $lib and $arch"
  # check if initramfs or piggyback is used
  if [ $piggyback -eq 1 ]; then
    echo "Using extra directory for test image creation"
    root=openadk/extra
    rm -rf openadk/extra 2>/dev/null
    mkdir openadk/extra 2>/dev/null
    if [ ! -z $suffix ]; then
      kernel=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}_${suffix}/${emulator}-${march}-initramfspiggyback-kernel
    else
      kernel=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}/${emulator}-${march}-initramfspiggyback-kernel
    fi
  else
    echo "Generating root filesystem for test run"
    root=$(mktemp -d /tmp/XXXX)
    if [ ! -z $suffix ]; then
      archive=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}_${suffix}/qemu-${march}-${lib}-initramfsarchive.tar.xz
      kernel=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}_${suffix}/qemu-${march}-initramfsarchive-kernel
    else
      archive=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}/${emulator}-${march}-${lib}-initramfsarchive.tar.xz
      kernel=openadk/firmware/${emulator}-${march}_${lib}_${cpu_arch}/${emulator}-${march}-initramfsarchive-kernel
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
  else
    echo "Creating initramfs filesystem"
    (cd $root; find . | cpio -o -C512 -Hnewc |xz --check=crc32 --stdout > ${topdir}/initramfs.${arch})
    rm -rf $root
    qemu_args="$qemu_args -initrd initramfs.${arch}"
  fi

  # qemu-ppc overwrites existing commandline
  if [ $noappend -eq 0 ]; then
    qemu_args="$qemu_args ${qemu_append}"
  fi

  echo "Now running the test ${test} in ${emulator} for architecture ${arch} and ${lib}"
  case $emulator in
    qemu)
      echo "${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot"
      ${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot | tee REPORT.${arch}.${emulator}.${test}.${libver}
      ;;
    nsim)
      echo "./openadk/scripts/nsim.sh ${arch} ${kernel}"
      ./openadk/scripts/nsim.sh ${arch} ${kernel} | tee REPORT.${arch}.${emulator}.${test}.${libver}
      ;;
  esac
  if [ $? -eq 0 ]; then
    echo "Test ${test} for ${arch} finished. See REPORT.${arch}.${emulator}.${test}.${libver}"
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

  if [ $debug -eq 1 ]; then
    DEFAULT="$DEFAULT ADK_VERBOSE=1"
  fi

  # build defaults for different tests
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
    case $lib in
      uclibc-ng)
        DEFAULT="$DEFAULT ADK_TEST_UCLIBC_NG_TESTSUITE=y"
        REBUILD=.rebuild.uclibc-ng
        ;;
      glibc)
        DEFAULT="$DEFAULT ADK_TEST_GLIBC_TESTSUITE=y"
        ;;
      musl)
        DEFAULT="$DEFAULT ADK_TEST_MUSL_TESTSUITE=y"
        ;;
    esac
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

  rm .config* .defconfig 2>/dev/null
  echo "Using following defaults: $DEFAULT"
  make $DEFAULT defconfig
  for pkg in $packages; do
    p=$(echo $pkg|tr '[:lower:]' '[:upper:]');printf "ADK_COMPILE_$p=y\nADK_PACKAGE_$p=y" >> .config
    yes|make oldconfig
  done
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
        version=1.0.10
      fi
      libver=uClibc-ng-${version}
      libdir=uClibc-ng
      ;;
    glibc)
      archlist=$arch_list_glibc
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=2.22
      fi
      libver=glibc-${version}
      libdir=glibc
      ;;
    musl)
      archlist=$arch_list_musl
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=1.1.12
      fi
      libver=musl-${version}
      libdir=musl
      ;;
    newlib)
      archlist=$arch_list_newlib
      if [[ $libcversion ]]; then
        version=$libcversion
      else
        version=2.2.0
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
    usrc=$(mktemp -d /tmp/XXXX)
    echo "Creating C library source tarball openadk/dl/${libver}.tar.xz"
    cp -a $libcsource $usrc/$libver
    mkdir -p $topdir/openadk/dl 2>/dev/null
    rm $topdir/openadk/dl/${libver}.tar.xz 2>/dev/null
    (cd $usrc && tar cJf $topdir/openadk/dl/${libver}.tar.xz ${libver} )
    touch $topdir/openadk/dl/${libver}.tar.xz.nohash
    # we need to clean system, when external source is used
    if [ $noclean -eq 0 ]; then
      clean=1
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
      tarball=openadk/firmware/${target_system}_${lib}_${target_suffix}/${target_system}-${lib}-${target_rootfs}.tar.xz
      scp $kernel root@${bootserver}:/tftpboot/${target_host}
      ssh -n root@${bootserver} "cd /tftpboot; ln -sf ${target_host} vmlinux"
      ssh -n root@${bootserver} "mkdir /nfsroot/${target_host} 2>/dev/null"
      xzcat $tarball | ssh root@${bootserver} "tar -xf - -C /nfsroot/${target_host}"
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
      if [ $cont -eq 1 ]; then
        if [ -f "REPORT.${arch}.${test}.${libver}" ]; then
          echo "Skipping already run test $test for $arch and $lib"
          continue
        fi
      fi
      if [ "$arch" = "$skiparchs" ]; then
        echo "Skipping $skiparchs"
        continue
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
            touch REPORT.${arch}.${test}.${libver}
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
