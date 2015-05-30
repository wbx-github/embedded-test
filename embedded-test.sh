#!/bin/sh
# Copyright © 2014-2015
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

# architecture specific notes:
#  sheb network card get no ip
#  sparc64 network card does not work right
#  ppcsf problem with busybox sort, broken startup order for glibc
#  m68k glibc toolchain building is broken at the moment 

# uClibc-ng
arch_list_uclibcng_quick="arm arc avr32 bfin crisv10 m68k m68k-nommu mipsel mips64el ppcsf sh sparc x86 x86_64 xtensa"
arch_list_uclibcng="arm armhf armeb arc arcbe avr32 bfin crisv10 crisv32 m68k m68k-nommu mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64el mips64eln64 ppc ppcsf sh sheb sparc x86 x86_64 xtensa"

# musl
arch_list_musl_quick="aarch64 arm microblazeel mipsel ppc sh x86 x86_64"
arch_list_musl="aarch64 arm armhf armeb microblazeel microblazebe mips mipssf mipsel mipselsf ppc sh sheb x86 x86_64"

# glibc
arch_list_glibc_quick="aarch64 arm microblazeel mipsel mips64eln64 nios2 ppcsf ppc64 sh sparc sparc64 tile x86 x86_64"
arch_list_glibc="aarch64 arm armhf armeb microblazeel microblazebe mips mipssf mipsel mipselsf mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 nios2 ppc ppcsf ppc64 sh sheb sparc sparc64 tile x86 x86_64"

topdir=$(pwd)
openadk_git=http://git.openadk.org/openadk.git

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
Syntax: $0 [ -l <libc> -a <arch> -t <tests> ]

Explanation:
	-l: c library to use (uclibc-ng|musl|glibc)
	-g: use latest git version of C library
	-a: architecture to check (otherwise all supported)
	-u: update openadk source via git pull, before building
	-s: use directory with source for C library
	-f: enable fast compile, after a failure no rebuild
	-d: enable debug output from OpenADK
	-c: clean OpenADK build directory before build
	-m: start a shell in Qemu system for manual testing
	-n: set NTP server for test run
	-p: add extra packages to build
	-q: use quick mode (no endian|abi|float combinations)
	-t: run tests (boot|libc|ltp|native)
	-h: help text
EOF

}

break=0
clean=0
shell=0
update=0
debug=0
git=0
fast=0
quick=0
ntp=

while getopts "bhfgumdqcn:a:s:l:t:p:" ch; do
        case $ch in
                m)
                        shell=1
                        ;;
                g)
                        git=1
                        ;;
                b)
                        break=1
                        ;;
                c)
                        clean=1
                        ;;
                d)
                        debug=1
                        ;;
                f)
                        fast=1
                        ;;
                q)
                        quick=1
                        ;;
                u)
                        update=1
                        ;;
                s)
                        source=$OPTARG
                        ;;
                l)
                        libc=$OPTARG
                        ;;
                n)
                        ntp=$OPTARG
                        ;;
                a)
                        archtolist=$OPTARG
                        ;;
                p)
                        pkgs=$OPTARG
                        ;;
                t)
                        tests=$OPTARG
                        ;;
		h)
			help
			exit 1
			;;
        esac
done
shift $((OPTIND - 1))

if [ -z "$libc" ];then
	libc="uclibc-ng musl glibc"
fi

if [ ! -d openadk ];then
	git clone $openadk_git
	if [ $? -ne 0 ];then
		echo "Cloning from $openadk_git failed."
		exit 1
	fi
else
	if [ $update -eq 1 ];then
		(cd openadk && git pull)
		if [ $? -ne 0 ];then
			echo "Updating from $openadk_git failed."
			exit 1
		fi
	fi
fi

runtest() {

	lib=$1
	arch=$2
	test=$3

	qemu=qemu-system-${arch}
	qemu_args=
	if [[ $ntp ]]; then
		qemu_append="-append ntpserver=$ntp"
	fi
	if [ $shell -eq 1 ]; then
		qemu_append="-append shell"
	fi
	noappend=0
	suffix=
	libdir=lib
	march=${arch}

	case ${arch} in
		aarch64)
			cpu_arch=aarch64
			qemu_machine=virt
			qemu_args="${qemu_args} -cpu cortex-a57 -netdev user,id=eth0 -device virtio-net-device,netdev=eth0"
			;;
		arm) 
			cpu_arch=arm
			qemu_machine=vexpress-a9
			suffix=soft_eabi
			dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
			qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
			;;
		armhf) 
			cpu_arch=arm
			march=arm
			qemu=qemu-system-${cpu_arch}
			qemu_machine=vexpress-a9
			suffix=hard_eabihf
			dtbdir=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}
			qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118 -dtb ${dtbdir}/vexpress-v2p-ca9.dtb"
			;;
		microblazeel)
			cpu_arch=microblazeel
			march=microblaze
			qemu_machine=petalogix-s3adsp1800
			;;
		microblazebe)
			cpu_arch=microblaze
			march=microblaze
			qemu=qemu-system-${march}
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
			march=ppc
			qemu=qemu-system-${cpu_arch}
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			qemu_machine=bamboo
			suffix=soft
			;;
		ppc)
			cpu_arch=ppc
			march=ppc
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
		sh) 
			cpu_arch=sh4
			qemu=qemu-system-${cpu_arch}
			qemu_machine=r2d
			qemu_args="${qemu_args} -monitor null -serial null -serial stdio"
			;;
		sheb) 
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
			qemu_args="${qemu_args} -device ne2k_pci,netdev=adk0 -netdev user,id=adk0"
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

	if ! which $qemu >/dev/null; then
		echo "Checking if $qemu is installed... failed"
		exit 1
	fi
	qemuver=$(${qemu} -version|awk '{ print $4 }')
	if [ $(echo $qemuver |sed -e "s#\.##g" -e "s#,##") -lt 210 ];then
		echo "Your qemu version is too old. Please update to 2.1 or greater"
		exit 1
	fi

	echo "Starting test for $lib and $arch"
	echo "Generating root filesystem for test run"
	root=$(mktemp -d /tmp/XXXX)
	if [ ! -z $suffix ]; then
		archive=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}/qemu-${march}-${lib}-initramfsarchive.tar.xz
		kernel=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}_${suffix}/qemu-${march}-initramfsarchive-kernel
	else
		archive=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}/qemu-${march}-${lib}-initramfsarchive.tar.xz
		kernel=openadk/firmware/qemu-${march}_${lib}_${cpu_arch}/qemu-${march}-initramfsarchive-kernel
	fi

	if [ ! -f $archive ];then
		echo "No root filesystem available for architecture ${arch} tried $archive"
		exit 1
	fi
	tar -xf $archive -C $root

cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
if [[ \$ntpserver ]]; then
	rdate \$ntpserver
else
	rdate time.fu-berlin.de
fi
file /bin/busybox
EOF

	if [ $test = "boot" ];then
cat >> ${root}/run.sh << EOF
for i in \$(ls /lib/*.so|grep -v libgcc);do
	size /bin/busybox
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
make run
exit
EOF
			;;
		esac

	fi
	chmod u+x ${root}/run.sh
	echo "Creating initramfs filesystem"
	(cd $root; find . | cpio -o -C512 -Hnewc |xz --check=crc32 --stdout > ${topdir}/initramfs.${arch})
	rm -rf $root

	# qemu-ppc overwrites existing commandline
	if [ $noappend -eq 0 ]; then
		qemu_args="$qemu_args ${qemu_append}"
	fi

	echo "Now running the test ${test} in qemu for architecture ${arch} and ${lib}"
	echo "${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic -initrd initramfs.${arch}"
	${qemu} -M ${qemu_machine} ${qemu_args} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic -initrd initramfs.${arch} | tee REPORT.${arch}.${test}.${libver}
	if [ $? -eq 0 ];then
		echo "Test ${test} for ${arch} finished. See REPORT.${arch}.${lib}.${test}.${version}"
		echo 
	else
		echo "Test ${test} failed for ${arch} with ${lib} ${version}."
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

	# always trigger regeneration of kernel config
	rm build_*_${lib}_${arch}*/linux/.config > /dev/null 2>&1

	# download and rebuild C library package
	if [ $fast -eq 0 ];then
		make package=$lib clean > /dev/null 2>&1
	fi

	DEFAULT="ADK_TARGET_LIBC=$lib ADK_TARGET_FS=initramfsarchive"

	if [ $debug -eq 1 ];then
		DEFAULT="$DEFAULT ADK_VERBOSE=1"
	fi
	if [ $git -eq 1 ];then
		DEFAULT="$DEFAULT ADK_LIBC_GIT=y"
	fi
	if [ $test = "boot" ];then
		DEFAULT="$DEFAULT ADK_TEST_BASE=y"
	fi
	if [ $test = "ltp" ];then
		DEFAULT="$DEFAULT ADK_TEST_LTP=y"
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
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=aarch64 ADK_TARGET_SYSTEM=qemu-aarch64"
			compile "$DEFAULT"
			;;
		arc)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_SYSTEM=toolchain-arc ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		arcbe)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arc ADK_TARGET_SYSTEM=toolchain-arc ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		arm)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_SYSTEM=qemu-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		armeb)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_SYSTEM=toolchain-arm ADK_TARGET_FLOAT=soft ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		armhf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=arm ADK_TARGET_SYSTEM=qemu-arm ADK_TARGET_FLOAT=hard ADK_TARGET_ENDIAN=little" 
			compile "$DEFAULT"
			;;
		avr32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=avr32 ADK_TARGET_SYSTEM=toolchain-avr32" 
			compile "$DEFAULT"
			;;
		bfin)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=bfin ADK_TARGET_SYSTEM=toolchain-bfin"
			compile "$DEFAULT"
			;;
		c6x)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=c6x ADK_TARGET_SYSTEM=toolchain-c6x"
			compile "$DEFAULT"
			;;
		crisv10)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv10"
			compile "$DEFAULT"
			;;
		crisv32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=cris ADK_TARGET_SYSTEM=toolchain-cris ADK_TARGET_CPU=crisv32"
			compile "$DEFAULT"
			;;
		m68k)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_SYSTEM=aranym-m68k"
			compile "$DEFAULT"
			;;
		m68k-nommu)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=m68k ADK_TARGET_SYSTEM=qemu-m68k"
			compile "$DEFAULT"
			;;
		microblazebe)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_SYSTEM=qemu-microblaze ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		microblazeel)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=microblaze ADK_TARGET_SYSTEM=qemu-microblaze ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		mips)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		mipssf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big ADK_TARGET_FLOAT=soft" 
			compile "$DEFAULT"
			;;
		mipsel)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		mipselsf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little ADK_TARGET_FLOAT=soft"
			compile "$DEFAULT"
			;;
		mips64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64n32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64n64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		mips64el)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64eln32)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64eln64)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		nios2)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=nios2 ADK_TARGET_SYSTEM=toolchain-nios2"
			compile "$DEFAULT"
			;;
		ppc)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_SYSTEM=qemu-ppc ADK_TARGET_QEMU=macppc ADK_TARGET_FLOAT=hard"
			compile "$DEFAULT"
			;;
		ppcsf)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=ppc ADK_TARGET_SYSTEM=qemu-ppc ADK_TARGET_QEMU=bamboo ADK_TARGET_FLOAT=soft"
			compile "$DEFAULT"
			;;
		sh)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		sheb)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		tile)
			DEFAULT="$DEFAULT ADK_APPLIANCE=new ADK_TARGET_ARCH=tile ADK_TARGET_SYSTEM=toolchain-tile"
			compile "$DEFAULT"
			;;
		*)
			DEFAULT="$DEFAULT ADK_APPLIANCE=test ADK_TARGET_ARCH=$arch ADK_TARGET_SYSTEM=qemu-$arch"
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
			if [ $quick -eq 1 ]; then
				archlist=$arch_list_uclibcng_quick
			else
				archlist=$arch_list_uclibcng
			fi
			version=1.0.2
			gitversion=git
			if [ $git -eq 1 ]; then
				libver=uClibc-ng-${gitversion}
			else
				libver=uClibc-ng-${version}
			fi
			libdir=uClibc-ng
			;;
		glibc)
			if [ $quick -eq 1 ]; then
				archlist=$arch_list_glibc_quick
			else
				archlist=$arch_list_glibc
			fi
			version=2.21
			gitversion=2.21.90
			if [ $git -eq 1 ]; then
				libver=glibc-${gitversion}
			else
				libver=glibc-${version}
			fi
			libdir=glibc
			;;
		musl)
			if [ $quick -eq 1 ]; then
				archlist=$arch_list_musl_quick
			else
				archlist=$arch_list_musl
			fi
			version=1.1.9
			gitversion=git
			if [ $git -eq 1 ]; then
				libver=musl-${gitversion}
			else
				libver=musl-${version}
			fi
			libdir=musl
			;;
	esac
	if [ ! -z $archtolist ]; then
		archlist="$archtolist"
	fi
	if [ ! -z $source ]; then
		if [ ! -d $source ]; then
			echo "Not a directory."
			exit 1
		fi
		if [ $fast -eq 0 ]; then
			usrc=$(mktemp -d /tmp/XXXX)
			echo "Creating source tarball openadk/dl/${libver}.tar.xz"
			cp -a $source $usrc/$libver
			mkdir -p $topdir/openadk/dl 2>/dev/null
			rm $topdir/openadk/dl/${libver}.tar.xz 2>/dev/null
			(cd $usrc && tar cJf $topdir/openadk/dl/${libver}.tar.xz ${libver} )
			touch $topdir/openadk/dl/${libver}.tar.xz.nohash
		fi
	fi

	echo "Architectures to test: $archlist"
	for arch in ${archlist}; do
		# start with a clean dir
		if [ $clean -eq 1 ]; then
			(cd openadk && make cleandir)
		fi
		if [ $break -eq 1 -a -f "REPORT.${arch}.${lib}.${tests}.${version}" ]; then
			echo "Skipping this test after last build break"
			continue
		fi
		echo "Compiling base system and toolchain for $lib and $arch"
		build $lib $arch notest
		if [ ! -z "$tests" ];then
			for test in ${tests}; do
				if [ $test = "boot" -o $test = "libc" -o $test = "ltp" -o $test = "native" ];then
					case $lib in 
					uclibc-ng)
						case $arch in
						arc|arcbe|armeb|avr32|bfin|c6x|crisv10|crisv32|microblazeel|microblazebe|m68k|m68k-nommu|nios2|sheb|mips64eln32|mips64n32)
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
						armeb|sheb)
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
						armeb|m68k|nios2|sheb|sparc64|tile)
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
					echo "Test $test is not valid. Allowed tests: boot libc ltp native"
					exit 1
				fi
			done
		fi
	done
done

echo "All tests finished."
exit 0
