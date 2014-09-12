#!/bin/sh
# Copyright © 2014
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
#  mips64n32/mips64eln32 produces segfaults on boot for uClibc/uClibc-ng
#  sheb network card get no ip
#  testsuite compile issues for m68k

arch_list_uclibcng="arm armhf bfin m68k-nommu mips mipsel mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64el mips64eln64 ppc-nofpu sh sheb sparc x86 x86_64 xtensa"
arch_list_uclibc="arm armhf arc arcbe avr32 bfin m68k-nommu mips mipsel mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64el mips64eln64 ppc-nofpu sh sheb sparc x86 x86_64 xtensa"
arch_list_musl="arm armhf mips mipsel ppc-nofpu sh sheb x86 x86_64"
arch_list_glibc="aarch64 arm armhf m68k mips mipsel mips64 mips64eln32 mips64n32 mips64n64 mips64el mips64eln32 mips64eln64 ppc-nofpu ppc64 sh sheb sparc sparc64 x86 x86_64"

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
	-l: c library to use (uclibc-ng|musl|glibc|uclibc)
	-g: use latest git version of C library
	-a: architecture to check (otherwise all supported)
	-u: update openadk source via git pull, before building
	-s: use directory with source for C library
	-d: enable debug output from OpenADK
	-c: clean OpenADK build directory before build
	-n: set NTP server for test run
	-t: run tests (boot|libc|ltp|native)
	-p: add extra packages to build
	-r: rebuild C library
	-m: start a shell in Qemu system for manual testing
	-h: help text
EOF

}

clean=0
shell=0
update=0
debug=0
git=0
rebuild=0

ntp=time.fu-berlin.de

while getopts "hgrumdcn:a:s:l:t:p:" ch; do
        case $ch in
                m)
                        shell=1
                        ;;
                g)
                        git=1
                        ;;
                c)
                        clean=1
                        ;;
                d)
                        debug=1
                        ;;
                u)
                        update=1
                        ;;
                r)
                        rebuild=1
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
                        archlist=$OPTARG
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
	libc="uclibc-ng uclibc musl glibc"
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
	qemu_append="ntp_server=$ntp"
	if [ $debug -eq 0 ];then
		qemu_append="$qemu_append quiet"
	fi
	if [ $shell -eq 1 ];then
		qemu_append="$qemu_append shell"
	fi
	suffix=
	psuffix=
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
			qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118"
			suffix=eabi
			psuffix=$suffix
			;;
		armhf) 
			cpu_arch=arm
			march=arm
			qemu=qemu-system-${cpu_arch}
			qemu_machine=vexpress-a9
			qemu_args="${qemu_args} -cpu cortex-a9 -net user -net nic,model=lan9118"
			suffix=eabihf
			psuffix=$suffix
			;;
		mips) 
			cpu_arch=mips
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			;;
		mipsel) 
			cpu_arch=mipsel
			march=mips
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			;;
		mips64) 
			cpu_arch=mips64
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abi32
			psuffix=o32
			;;
		mips64n32) 
			cpu_arch=mips64
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abin32
			psuffix=n32
			;;
		mips64n64) 
			cpu_arch=mips64
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abi64
			psuffix=n64
			;;
		mips64el) 
			cpu_arch=mips64el
			march=mips64
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abi32
			psuffix=o32
			;;
		mips64eln32) 
			cpu_arch=mips64el
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abin32
			psuffix=n32
			;;
		mips64eln64) 
			cpu_arch=mips64el
			march=mips64
			qemu=qemu-system-${cpu_arch}
			qemu_machine=malta
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			suffix=abi64
			psuffix=n64
			;;
		ppc-nofpu)
			cpu_arch=ppc
			march=ppc
			qemu=qemu-system-${cpu_arch}
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			qemu_machine=bamboo
			;;
		ppc)
			cpu_arch=ppc
			march=ppc
			qemu=qemu-system-${cpu_arch}
			qemu_args="${qemu_args} -device e1000,netdev=adk0 -netdev user,id=adk0"
			qemu_machine=mac99
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
			cpu_arch=i486
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
			suffix=x32
			;;
		xtensa) 
			cpu_arch=xtensa
			qemu=qemu-system-${cpu_arch}
			qemu_machine=lx60
			qemu_args="${qemu_args} -cpu dc232b"
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

	case $lib in
		uclibc-ng)
			prefix=uclibc
			;;
		glibc)
			prefix=gnu
			;;
		*)
			prefix=$libc
			;;
	esac
	cross=${cpu_arch}-openadk-linux-${prefix}${suffix}
	if [ -z $psuffix ];then
		TCPATH=${topdir}/openadk/toolchain_qemu-${march}_${lib}_${cpu_arch}
	else
		TCPATH=${topdir}/openadk/toolchain_qemu-${march}_${lib}_${cpu_arch}_${psuffix}
	fi
	export PATH="${TCPATH}/usr/bin:$PATH"

	if ! which ${cross}-gcc >/dev/null; then
		echo "Checking if ${cross}-gcc is installed... failed"
		exit 1
	fi

	echo "Starting test for $lib and ${arch}"
	echo "Generating root filesystem for test run"
	root=$(mktemp -d /tmp/XXXX)
	if [ ! -f openadk/firmware/qemu-${march}_${lib}/qemu-${march}-${lib}-initramfsarchive.tar.gz ];then
		echo "No root filesystem available for architecture ${arch}"
		exit 1
	fi
	tar -xf openadk/firmware/qemu-${march}_${lib}/qemu-${march}-${lib}-initramfsarchive.tar.gz -C $root

	if [ $test = "boot" ];then
cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
rdate -n \$ntp_server
file /bin/busybox
for i in \$(ls /lib/*.so|grep -v libgcc);do
	size \$i
done
exit
EOF
	fi
	if [ $test = "ltp" ];then
cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
rdate -n \$ntp_server
/opt/ltp/runltp
exit
EOF
	fi
	if [ $test = "libc" ];then

		case $lib in
			uclibc-ng|uclibc)
cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
rdate -n \$ntp_server
cd /opt/$libc/test
CROSS_COMPILE=": ||" make UCLIBC_ONLY=y -k run
exit
EOF
			;;
			musl|glibc)
cat > ${root}/run.sh << EOF
#!/bin/sh
uname -a
rdate -n \$ntp_server
cd /opt/libc-test
make run
exit
EOF
			;;
		esac

	fi
	chmod u+x ${root}/run.sh

	kernel=openadk/firmware/qemu-${march}_${lib}/qemu-${march}-initramfsarchive-kernel

	echo "Creating initramfs filesystem"
	(cd $root; find . | cpio -o -C512 -Hnewc |xz --check=crc32 --stdout > ${topdir}/initramfs.${arch})
	rm -rf $root

	echo "Now running the tests in qemu for architecture ${arch} and ${lib}"
	echo "${qemu} -M ${qemu_machine} ${qemu_args} -append ${qemu_append} -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic -initrd initramfs.${arch}"
	${qemu} -M ${qemu_machine} ${qemu_args} -append "${qemu_append}" -kernel ${kernel} -qmp tcp:127.0.0.1:4444,server,nowait -no-reboot -nographic -initrd initramfs.${arch} | tee REPORT.${arch}.${lib}.${test}.${version}
	if [ $? -eq 0 ];then
		echo "Test for ${arch} finished. See REPORT.${arch}.${lib}.${test}.${version}"
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
	rm build_*_${lib}_${arch}*/linux/.config 2>/dev/null
	if [ $rebuild -eq 1 ];then
		rm dl/$lib*
		make package=$lib clean
	fi

	DEFAULT="ADK_TARGET_LIBC=$lib ADK_TARGET_FS=initramfsarchive ADK_TARGET_COLLECTION=test"

	if [ $debug -eq 1 ];then
		DEFAULT="$DEFAULT VERBOSE=1"
	fi
	if [ $git -eq 1 ];then
		DEFAULT="$DEFAULT ADK_LIBC_GIT=y"
	fi
	if [ ! -z $source ];then
		DEFAULT="$DEFAULT ADK_NO_CHECKSUM=y"
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
			uclibc)
				DEFAULT="$DEFAULT ADK_TEST_UCLIBC_TESTSUITE=y"
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
			uclibc)
				DEFAULT="$DEFAULT ADK_TEST_UCLIBC_NATIVE=y"
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
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=aarch64 ADK_TARGET_SYSTEM=qemu-aarch64"
			compile "$DEFAULT"
			;;
		arc)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=arc ADK_TARGET_SYSTEM=toolchain-arc ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		arcbe)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=arc ADK_TARGET_SYSTEM=toolchain-arc ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		arm)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=arm ADK_TARGET_SYSTEM=qemu-arm ADK_TARGET_ABI=eabi ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		armhf)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=arm ADK_TARGET_SYSTEM=qemu-arm ADK_TARGET_ABI=eabihf ADK_TARGET_ENDIAN=little" 
			compile "$DEFAULT"
			;;
		bfin)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=bfin ADK_TARGET_SYSTEM=toolchain-bfin"
			compile "$DEFAULT"
			;;
		m68k)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=m68k ADK_TARGET_SYSTEM=aranym-m68k"
			compile "$DEFAULT"
			;;
		m68k-nommu)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=m68k ADK_TARGET_SYSTEM=qemu-m68k"
			compile "$DEFAULT"
			;;
		mips)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		mipsel)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips ADK_TARGET_SYSTEM=qemu-mips ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		mips64)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64n32)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64n64)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=big ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		mips64el)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=o32"
			compile "$DEFAULT"
			;;
		mips64eln32)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n32"
			compile "$DEFAULT"
			;;
		mips64eln64)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=mips64 ADK_TARGET_SYSTEM=qemu-mips64 ADK_TARGET_ENDIAN=little ADK_TARGET_ABI=n64"
			compile "$DEFAULT"
			;;
		ppc-nofpu)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=ppc ADK_TARGET_SYSTEM=qemu-ppc"
			compile "$DEFAULT"
			;;
		sh)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=little"
			compile "$DEFAULT"
			;;
		sheb)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=sh ADK_TARGET_SYSTEM=qemu-sh ADK_TARGET_ENDIAN=big"
			compile "$DEFAULT"
			;;
		*)
			DEFAULT="$DEFAULT ADK_TARGET_ARCH=$1 ADK_TARGET_SYSTEM=qemu-$1"
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
			if [ -z "$archlist" ];then
				archlist=$arch_list_uclibcng
			fi
			version=1.0.0
			gitversion=1.0.0-git
			libver=uClibc-ng-${gitversion}
			libdir=uClibc-ng
			;;
		uclibc)
			if [ -z "$archlist" ];then
				archlist=$arch_list_uclibc
			fi
			version=0.9.33.2
			gitversion=0.9.34-git
			libver=uClibc-${gitversion}
			libdir=uClibc
			;;
		glibc)
			if [ -z "$archlist" ];then
				archlist=$arch_list_glibc
			fi
			version=2.20
			gitversion=2.19.90
			libver=glibc-${gitversion}
			libdir=glibc
			;;
		musl)
			if [ -z "$archlist" ];then
				archlist=$arch_list_musl
			fi
			version=1.1.4
			gitversion=git
			libver=musl-${gitversion}
			libdir=musl
			;;
	esac
	if [ ! -z $source ];then
		if [ ! -d $source ];then
			echo "Not a directory."
			exit 1
		fi
		git=1
		usrc=$(mktemp -d /tmp/XXXX)
		echo "Creating source tarball openadk/dl/${libver}.tar.xz"
		cp -a $source $usrc/$libver
		mkdir -p $topdir/openadk/dl 2>/dev/null
		rm $topdir/openadk/dl/${libver}.tar.xz 2>/dev/null
		(cd $usrc && tar cJf $topdir/openadk/dl/${libver}.tar.xz ${libver} )
	fi

	for arch in ${archlist}; do
		# start with a clean dir
		if [ $clean -eq 1 ];then
			(cd openadk && make cleandir)
		fi
		echo "Compiling base system and toolchain for $lib and $arch"
		build $lib $arch notest
		if [ ! -z "$tests" ];then
			for test in ${tests}; do
				if [ $test = "boot" -o $test = "libc" -o $test = "ltp" -o $test = "native" ];then
					case $arch in
						arc|arcbe|avr32|bfin|m68k|m68k-nommu|ppc|sheb|mips64eln32|mips64n32)
							echo "runtime tests disabled for $arch."
							;;
						*)
							build $lib $arch $test
							runtest $lib $arch $test
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
