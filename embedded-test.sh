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

# architecture specific notes:
#  sheb network card get no ip
#  m68k glibc toolchain building is broken at the moment 

# uClibc-ng
arch_list_uclibcng="armv5 armv7 armeb arcv1 arcv2 arcv1-be arcv2-be avr32 bfin c6x crisv10 crisv32 h8300 m68k m68k-nommu metag microblazeel microblazebe mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64el mips64eln64 or1k ppc ppcsf sh4 sh4eb sparc x86 x86_64 xtensa"

# musl
arch_list_musl="aarch64 armv5 armv7 armeb microblazeel microblazebe mips mipssf mipsel mipselsf or1k ppc sh4 sh4eb x86 x86_64"

# glibc
arch_list_glibc="aarch64 armv5 armv7 armeb microblazeel microblazebe mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 nios2 ppc ppcsf ppc64 sh4 sh4eb sparc sparc64 tile x86 x86_64"

topdir=$(pwd)
giturl=http://git.openadk.org/openadk.git
valid_libc="uclibc-ng musl glibc"
valid_tests="boot libc ltp mksh native"

tools='make git wget xz cpio tar awk sed'
f=0
for tool in $tools; do
	if ! which $tool >/dev/null; then
		echo "Checking if $tool is installed... failed"
		f=1
	fi
done
if [ $f -eq 1 ];then exit 1; fi

help() {
	cat >&2 <<EOF
Syntax: $0 [ --libc=<libc> --arch=<arch> --tests=<tests> ]

Explanation:
	--libc=<libc>             c library to use (${valid_libc})
	--arch=<arch>             architecture to check (otherwise all supported)
	--skiparch=<arch>         architectures to skip when all choosen
	--tests=<tests>           run tests (${valid_tests})
	--source=<dir>            use directory with source for C library
	--ntp=<ntpserver>         set NTP server for test run
	--packages=<packagelist>  add extra packages to the build
	--update                  update OpenADK source via git pull, before building
	--continue                continue on a broken build
	--clean                   clean OpenADK build directory before build
	--debug                   enable debug output from OpenADK
	--shell                   start a shell instead auf autorun of test
	--help                    this help text
EOF
	exit 1
}

continue=0
clean=0
shell=0
update=0
debug=0
piggyback=0
ntp=""
libc=""

while [[ $1 != -- && $1 = -* ]]; do case $1 { 
  (--clean) clean=1; shift ;;
  (--debug) debug=1; shift ;;
  (--update) update=1; shift ;;
  (--continue) continue=1; shift ;;
  (--shell) shell=1 shift ;;
  (--libc=*) libc=${1#*=}; shift ;;
  (--arch=*) archs=${1#*=}; shift ;;
  (--skiparch=*) skiparchs=${1#*=}; shift ;;
  (--tests=*) tests=${1#*=}; shift ;;
  (--source=*) source=${1#*=}; shift ;;
  (--ntp=*) ntp=${1#*=}; shift ;;
  (--help) help; shift ;;
  (--*) echo "unknown option $1"; exit 1 ;; 
  (-*) help ;;
}; done

if [ -z "$libc" ];then
	libc="uclibc-ng musl glibc"
fi

if [ ! -d openadk ];then
	git clone $giturl
	if [ $? -ne 0 ];then
		echo "Cloning from $giturl failed."
		exit 1
	fi
else
	if [ $update -eq 1 ];then
		(cd openadk && git pull)
		if [ $? -ne 0 ];then
			echo "Updating from $giturl failed."
			exit 1
		fi
	fi
fi

runtest() {

	lib=$1
	arch=$2
	test=$3

	emulator=qemu
	qemu=qemu-system-${arch}
	qemu_args=
	if [ $ntp ]; then
		qemu_append="-append ntpserver=$ntp"
	fi
	if [ $shell -eq 1 ]; then
		qemu_append="-append shell"
	fi
	noappend=0
	piggyback=0
	suffix=
	libdir=lib
	march=${arch}

	case ${arch} in
		aarch64)
			cpu_arch=aarch64
			qemu_machine=virt
			qemu_args="${qemu_args} -cpu cortex-a57 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
			;;
		armv5)
			cpu_arch=arm
			march=arm-versatilepb
			qemu=qemu-system-${cpu_arch}
			qemu_machine=versatilepb
			suffix=soft_eabi
			dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
			qemu_args="${qemu_args} -cpu arm926 -net user -net nic,model=smc91c111"
			;;
		armv7)
			cpu_arch=arm
			march=arm-vexpress-a9
			qemu=qemu-system-${cpu_arch}
			qemu_machine=vexpress-a9
			suffix=hard_eabihf
			dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
			qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
			;;
		arcv1)
			emulator=nsim
			cpu_arch=arc
			piggyback=1
			;;
		arcv2)
			emulator=nsim
			cpu_arch=arc
			piggyback=1
			;;
		crisv32)
			cpu_arch=crisv32
			march=cris
			qemu=qemu-system-${march}
			qemu_machine=axis-dev88
			piggyback=1
			;;
		metag)
			cpu_arch=metag
			march=meta
			qemu=qemu-system-${march}
			qemu_args="${qemu_args} -display none -device da,exit_threads=1 -chardev stdio,id=chan1 -chardev pty,id=chan2"
			piggyback=1
			;;
		microblazeel)
			cpu_arch=microblazeel
			march=microblaze-ml605
			qemu_machine=petalogix-s3adsp1800
			;;
		microblazebe)
			cpu_arch=microblaze
			march=microblaze-ml605
			qemu=qemu-system-${cpu_arch}
			qemu_machine=petalogix-s3adsp1800
			;;
		mips) 
			cpu_arch=mips
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=hard
			;;
		mipssf) 
			cpu_arch=mips
			march=mips
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=soft
			;;
		mipsel) 
			cpu_arch=mipsel
			march=mips
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=hard
			;;
		mipselsf) 
			cpu_arch=mipsel
			march=mips
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=soft
			;;
		mips64) 
			cpu_arch=mips64
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=o32
			;;
		mips64n32) 
			cpu_arch=mips64
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=n32
			;;
		mips64n64) 
			cpu_arch=mips64
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=n64
			;;
		mips64el) 
			cpu_arch=mips64el
			march=mips64
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=o32
			;;
		mips64eln32) 
			cpu_arch=mips64el
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=n32
			;;
		mips64eln64) 
			cpu_arch=mips64el
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=n64
			;;
		ppcsf)
			cpu_arch=ppc
			march=ppc-bamboo
			qemu=qemu-system-${cpu_arch}
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			qemu_machine=bamboo
			suffix=soft
			;;
		ppc)
			cpu_arch=ppc
			march=ppc-macppc
			qemu=qemu-system-${cpu_arch}
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			qemu_machine=mac99
			suffix=hard
			noappend=1
			;;
		powerpc64|ppc64) 
			cpu_arch=ppc64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=pseries
			;;
		sh4) 
			cpu_arch=sh4
			qemu=qemu-system-${cpu_arch}
			qemu_machine=r2d
			qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
			;;
		sh4eb) 
			cpu_arch=sh4eb
			march=sh
			qemu=qemu-system-${cpu_arch}
			qemu_machine=r2d
			qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
			;;
		sparc) 
			cpu_arch=sparc
			qemu_machine=SS-5
			;;
		sparc64) 
			cpu_arch=sparc64
			qemu_machine=sun4u
			qemu_args="${qemu_args} -net nic,model=e1000 -net user"
			;;
		x86) 
			cpu_arch=i686
			qemu=qemu-system-i386
			qemu_machine=pc
			qemu_args="${qemu_args}"
			;;
		x86_64) 
			cpu_arch=x86_64
			qemu_machine=pc
			libdir=lib64
			;;
		x86_64_x32) 
			cpu_arch=x86_64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=pc
			libdir=libx32
			;;
		xtensa) 
			cpu_arch=xtensa
			qemu=qemu-system-${cpu_arch}
			qemu_machine=lx60
			qemu_args="${qemu_args} -cpu dc233c"
			;;
		*) 
			echo "architecture ${arch} not supported"; exit 1;;
	esac

	case $emulator in
		qemu) 
			echo "Using QEMU as emulator"
			if ! which $qemu >/dev/null; then
				echo "Checking if $qemu is installed... failed"
				exit 1
			fi
			qemuver=$(${qemu} -version|awk '{ print $4 }')
			if [ $(echo $qemuver |sed -e "s#\.##g" -e "s#,##") -lt 210 ];then
				echo "Your qemu version is too old. Please update to 2.1 or greater"
				exit 1
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
			echo "emulator/simulator not supported"; exit 1;;
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

		if [ ! -f $archive ];then
			echo "No root filesystem available for architecture ${arch} tried $archive"
			exit 1
		fi
		tar -xf $archive -C $root
	fi

	# creating test script to be run on boot
cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
if [ \$ntpserver ]; then
	rdate \$ntpserver
else
	rdate time.fu-berlin.de
fi
EOF

	if [ $test = "boot" ];then
cat >> ${root}/run.sh << EOF
file /bin/busybox
size /bin/busybox
for i in \$(ls /lib/*.so|grep -v libgcc);do
	size \$i
done
exit
EOF
	fi
	if [ $test = "ltp" ];then
cat >> ${root}/run.sh << EOF
/opt/ltp/runltp
exit
EOF
	fi
	if [ $test = "mksh" ];then
cat >> ${root}/run.sh << EOF
mksh /opt/mksh/test.sh
exit
EOF
	fi
	if [ $test = "libc" ];then

		case $lib in
			uclibc-ng)
cat >> ${root}/run.sh << EOF
cd /opt/uclibc-ng/test
sh ./uclibcng-testrunner.sh
exit
EOF
			;;
			musl|glibc)
cat >> ${root}/run.sh << EOF
cd /opt/libc-test
CC=: make run
exit
EOF
			;;
		esac

	fi
	chmod u+x ${root}/run.sh

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
			echo "${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic"
			${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic | tee REPORT.${arch}.${test}.${libver}
			;;
		nsim)
			echo "./openadk/scripts/nsim.sh ${arch} ${kernel}"
			./openadk/scripts/nsim.sh ${arch} ${kernel} | tee REPORT.${arch}.${test}.${libver}
			;;
	esac
	if [ $? -eq 0 ];then
		echo "Test ${test} for ${arch} finished. See REPORT.${arch}.${test}.${libver}"
		echo 
	else
		echo "Test ${test} failed for ${arch} with ${lib} ${libver}."
		echo 
	fi
}

compile() {
	rm .config* .defconfig 2>/dev/null
	make $1 defconfig
	for pkg in $pkgs; do p=$(echo $pkg|tr '[:lower:]' '[:upper:]');printf "ADK_COMPILE_$p=y\nADK_PACKAGE_$p=y" >> .config;done
	make $1 all
}

build() {

	lib=$1
	arch=$2
	test=$3

	cd openadk
	make prereq

	make package=$lib clean > /dev/null 2>&1

	DEFAULT="ADK_TARGET_LIBC=$lib"
	if [ $debug -eq 1 ];then
		DEFAULT="$DEFAULT ADK_VERBOSE=1"
	fi
	if [ $test = "boot" ];then
		DEFAULT="$DEFAULT ADK_TEST_BASE=y"
	fi
	if [ $test = "ltp" ];then
		DEFAULT="$DEFAULT ADK_TEST_LTP=y"
	fi
	if [ $test = "mksh" ];then
		DEFAULT="$DEFAULT ADK_TEST_MKSH=y"
	fi
	if [ $test = "libc" ];then
		case $lib in
			uclibc-ng)
				DEFAULT="$DEFAULT ADK_TEST_UCLIBC_NG_TESTSUITE=y"
				;;
			glibc)
				DEFAULT="$DEFAULT ADK_TEST_GLIBC_TESTSUITE=y"
				;;
			musl)
				DEFAULT="$DEFAULT ADK_TEST_MUSL_TESTSUITE=y"
				;;
		esac
	fi
	if [ $test = "native" ];then
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
	case $arch in
		aarch64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=aarch64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-aarch64"
			compile "$DEFAULT"
			;;
		arcv1)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv1 ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		arcv2)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv2 ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		arcv1-be)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv1 ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		arcv2-be)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=nsim-arcv2 ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		armv5)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-versatilepb"
			compile "$DEFAULT"
			;;
		armeb)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		armv7)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-arm-vexpress-a9" 
			compile "$DEFAULT"
			;;
		avr32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=avr32 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-avr32" 
			compile "$DEFAULT"
			;;
		bfin)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=bfin ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-bfin"
			compile "$DEFAULT"
			;;
		c6x)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=c6x ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-c6x"
			compile "$DEFAULT"
			;;
		crisv10)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv10"
			compile "$DEFAULT"
			;;
		crisv32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=cris ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-cris"
			compile "$DEFAULT"
			;;
		h8300)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=h8300 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-h8300"
			compile "$DEFAULT"
			;;
		m68k)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-m68k-q800"
			compile "$DEFAULT"
			;;
		m68k-nommu)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-m68k-mcf5208"
			compile "$DEFAULT"
			;;
		metag)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=metag ADK_TARGET_FS=initramfspiggyback ADK_TARGET_SYSTEM=qemu-metag"
			compile "$DEFAULT"
			;;
		microblazebe)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-ml605 ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		microblazeel)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-microblaze-ml605 ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		mips)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		mipssf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft" 
			compile "$DEFAULT"
			;;
		mipsel)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		mipselsf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
			compile "$DEFAULT"
			;;
		mips64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64n32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64n64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		mips64el)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64eln32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64eln64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		nios2)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=nios2 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-nios2"
			compile "$DEFAULT"
			;;
		or1k)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=or1k ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-or1k"
			compile "$DEFAULT"
			;;
		ppc)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-macppc ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		ppcsf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc-bamboo ADK_TARGET_FLOAT=soft"
			compile "$DEFAULT"
			;;
		ppc64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc64 ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-ppc64 ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		sh4)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		sh4eb)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		tile)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=tile ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=toolchain-tile"
			compile "$DEFAULT"
			;;
		*)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=$arch ADK_TARGET_FS=initramfsarchive ADK_TARGET_SYSTEM=qemu-$arch"
			compile "$DEFAULT"
			;;
	esac
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
			version=1.0.9
			libver=uClibc-ng-${version}
			libdir=uClibc-ng
			;;
		glibc)
			archlist=$arch_list_glibc
			version=2.22
			libver=glibc-${version}
			libdir=glibc
			;;
		musl)
			archlist=$arch_list_musl
			version=1.1.11
			libver=musl-${version}
			libdir=musl
			;;
		*)
			echo "$lib not supported"
			exit 1
			;;
	esac
	if [ ! -z $archs ]; then
		archlist="$archs"
	fi
	if [ ! -z $source ]; then
		if [ ! -d $source ]; then
			echo "Not a directory."
			exit 1
		fi
		usrc=$(mktemp -d /tmp/XXXX)
		echo "Creating source tarball openadk/dl/${libver}.tar.xz"
		cp -a $source $usrc/$libver
		mkdir -p $topdir/openadk/dl 2>/dev/null
		rm $topdir/openadk/dl/${libver}.tar.xz 2>/dev/null
		(cd $usrc && tar cJf $topdir/openadk/dl/${libver}.tar.xz ${libver} )
		touch $topdir/openadk/dl/${libver}.tar.xz.nohash
	fi

	# start with a clean dir
	if [ $clean -eq 1 ]; then
		echo "cleaning openadk build directory"
		(cd openadk && make cleandir)
	fi
	if [ ! -z "$tests" ];then
		testinfo="$tests testing"
	else
		testinfo="toolchain testing"
	fi
	echo "Summary: testing $archlist with C library $lib and $testinfo"
	sleep 2
	for arch in ${archlist}; do
		if [ $continue -eq 1 -a -f "REPORT.${arch}.${tests}.${libver}" ]; then
			echo "Skipping this test after last build break"
			continue
		fi
		if [ "$arch" = "$skiparchs" ];then
			echo "Skipping $skiparchs"
			continue
		fi
		echo "Compiling base system and toolchain for $lib and $arch"
		build $lib $arch notest
		if [ ! -z "$tests" ];then
			for test in ${tests}; do
				if [ $test = "boot" -o $test = "libc" -o $test = "ltp" -o $test = "native" -o $test = "mksh" ];then
					case $lib in 
					uclibc-ng)
						case $arch in
						arcv1-be|arcv2-be|armeb|avr32|bfin|c6x|crisv10|h8300|lm32|microblazeel|microblazebe|m68k|m68k-nommu|nios2|or1k|sh4eb)
							echo "runtime tests disabled for $arch."
							;;
						*)
							build $lib $arch $test
							runtest $lib $arch $test
							;;
						esac
						;;
					musl)
						case $arch in
						armeb|or1k|sh4eb)
							echo "runtime tests disabled for $arch."
							;;
						*)
							build $lib $arch $test
							runtest $lib $arch $test
							;;
						esac
						;;
					glibc)
						case $arch in
						armeb|m68k|nios2|sh4eb|tile)
							echo "runtime tests disabled for $arch."
							;;
						*)
							build $lib $arch $test
							runtest $lib $arch $test
							;;
						esac
						;;
					esac
				else
					echo "Test $test is not valid. Allowed tests: $valid_tests"
					exit 1
				fi
			done
		fi
	done
done

echo "All tests finished."
exit 0
