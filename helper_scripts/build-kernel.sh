#!/bin/sh
# usage: build-kernel.sh [JOBS] [LOCALVERSION] [OUT]
# example: sh build-kernel.sh 16 -scxkvm /out
set -eu

usage() {
  echo "usage: $0 [JOBS] [LOCALVERSION] [OUT]" >&2
  echo "  JOBS         make -j (default: nproc)" >&2
  echo "  LOCALVERSION uname -r suffix, include the leading dash (default: -scxkvm)" >&2
  echo "  OUT          install prefix inside this environment (default: /out)" >&2
  exit 2
}

case "${1:-}" in
  -h|--help) usage ;;
esac

JOBS=${1:-$(nproc)}
LOCALVERSION=${2:--scxkvm}
OUT=${3:-/out}

echo "JOBS=$JOBS LOCALVERSION=$LOCALVERSION OUT=$OUT"

make defconfig
make kvm_guest.config

scripts/config \
  --enable MODULES --enable MODULE_UNLOAD --enable SMP --set-val NR_CPUS 256 \
  --enable HYPERVISOR_GUEST --enable PARAVIRT --enable PARAVIRT_SPINLOCKS \
  --enable KVM_GUEST --enable PVH --enable ACPI --enable ACPI_PROCESSOR \
  --enable PCI --enable PCI_MSI \
  --enable VIRTIO --enable VIRTIO_MENU --enable VIRTIO_PCI --enable VIRTIO_PCI_LEGACY \
  --enable VIRTIO_BLK --enable VIRTIO_NET --enable VIRTIO_CONSOLE \
  --enable VIRTIO_BALLOON --enable VIRTIO_INPUT --enable VIRTIO_FS \
  --enable HW_RANDOM --enable HW_RANDOM_VIRTIO \
  --enable SCSI --enable SCSI_LOWLEVEL --enable SCSI_VIRTIO --enable BLK_DEV_SD \
  --enable NET_9P --enable NET_9P_VIRTIO --enable 9P_FS --enable 9P_FS_POSIX_ACL \
  --enable FUSE_FS \
  --enable TTY --enable SERIAL_8250 --enable SERIAL_8250_CONSOLE --enable SERIAL_8250_PCI \
  --enable BLK_DEV_INITRD --enable RD_GZIP --enable RD_XZ --enable RD_ZSTD \
  --enable DEVTMPFS --enable DEVTMPFS_MOUNT \
  --enable TMPFS --enable TMPFS_POSIX_ACL \
  --enable UNIX --enable INOTIFY_USER --enable PROC_FS --enable SYSFS \
  --enable EXT4_FS --enable EXT4_FS_POSIX_ACL --enable EXT4_FS_SECURITY --enable FS_POSIX_ACL \
  --enable BINFMT_ELF --enable BINFMT_SCRIPT --enable SYSVIPC \
  --enable NET --enable INET --enable IPV6 --enable PACKET \
  --enable NETDEVICES --enable NET_CORE --enable ETHERNET \
  --enable IP_PNP --enable IP_PNP_DHCP \
  --enable HIGH_RES_TIMERS --enable NO_HZ_IDLE --enable HZ_1000 \
  --enable CGROUPS --enable CGROUP_SCHED --enable FAIR_GROUP_SCHED --enable CFS_BANDWIDTH \
  --enable BLK_CGROUP --enable CGROUP_BPF --enable CGROUP_PIDS --enable MEMCG --enable CPUSETS \
  --enable NAMESPACES --enable PID_NS --enable NET_NS --enable USER_NS \
  --enable BPF --enable BPF_SYSCALL --enable BPF_JIT \
  --enable BPF_JIT_ALWAYS_ON --enable BPF_JIT_DEFAULT_ON \
  --enable BPF_EVENTS --enable SCHED_CLASS_EXT \
  --enable DEBUG_INFO --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
  --enable DEBUG_INFO_BTF --enable DEBUG_INFO_BTF_MODULES \
  --disable DEBUG_INFO_REDUCED \
  --enable KALLSYMS --enable KALLSYMS_ALL \
  --enable IKCONFIG --enable IKCONFIG_PROC --enable IKHEADERS \
  --enable FUNCTION_TRACER --enable DYNAMIC_FTRACE --enable FTRACE --enable FTRACE_SYSCALLS \
  --enable KPROBES --enable KPROBE_EVENTS --enable UPROBES --enable DEBUG_FS --enable STACKTRACE \
  --enable SCHED_AUTOGROUP --enable SCHED_CORE --enable SCHED_MC \
  --enable NUMA --enable NUMA_BALANCING \
  --disable PREEMPT_NONE --disable PREEMPT_VOLUNTARY \
  --enable PREEMPT --enable PREEMPT_DYNAMIC

make olddefconfig

for s in CONFIG_SCHED_CLASS_EXT CONFIG_DEBUG_INFO_BTF CONFIG_BPF_JIT_ALWAYS_ON \
         CONFIG_KVM_GUEST CONFIG_VIRTIO_PCI CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET \
         CONFIG_9P_FS CONFIG_NET_9P_VIRTIO CONFIG_EXT4_FS \
         CONFIG_KALLSYMS_ALL CONFIG_FUNCTION_TRACER
do
  grep -q "^${s}=y" .config || { echo "FATAL $s"; exit 1; }
done

make -j"$JOBS" LOCALVERSION="$LOCALVERSION" bzImage modules

rm -rf "$OUT"
mkdir -p "$OUT"
cp -f arch/x86/boot/bzImage "$OUT/bzImage"
cp -f vmlinux "$OUT/vmlinux"
cp -f System.map "$OUT/System.map"
cp -f .config "$OUT/config"

make LOCALVERSION="$LOCALVERSION" modules_install INSTALL_MOD_PATH="$OUT"
make headers_install INSTALL_HDR_PATH="$OUT"

make -s kernelrelease LOCALVERSION="$LOCALVERSION"
ls -l "$OUT/bzImage" "$OUT/lib/modules"
