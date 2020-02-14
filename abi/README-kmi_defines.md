The following header files are excluded from the set of header considered for
AOSP GKI KMI for the purpose of tracking compile time #define constants.

They are excluded because their inclusion in the .kmi.incs.c files causes
preprocessing errors related to macros expected to be pre-defined by the file
that includes the header.

Each one of these header files and its uses was examined and they are
appropriately excluded, the rationales for their exclusion follow:

include/rdma/uverbs_named_ioctl.h
  - only has defines macros with arguments
  - this header file is used by these kernel modules:
        drivers/infiniband/core/ib_uverbs.ko.lka
        drivers/infiniband/hw/mlx5/mlx5_ib.ko.lka
  - does not introduce compile time #define constants
  - furthermore infiniband is not relevant to AOSP GKI

include/uapi/linux/patchkey.h
  - only defines macros with arguments
  - can not be included directly because of internal check for
        _LINUX_PATCHKEY_H_INDIRECT
  - defines _PATCHKEY(id) which chould be used to generate ABI values this
    is part of uapi, so user mode API stability shold prevent this from
    changing and causing KMI incompatibility
  - this header file is used by these kernel modules:
        drivers/media/usb/cx231xx/cx231xx-alsa.ko
        drivers/media/usb/em28xx/em28xx-alsa.ko
        sound/drivers/opl3/snd-opl3-synth.ko
        sound/drivers/opl3/snd-opl3-lib.ko
        sound/core/seq/oss/snd-seq-oss.ko
        sound/core/oss/snd-mixer-oss.ko
        sound/core/oss/snd-pcm-oss.ko
        sound/pci/ymfpci/snd-ymfpci.ko
        sound/pci/riptide/snd-riptide.ko
        sound/pci/snd-cs4281.ko
        sound/pci/snd-cmipci.ko
        sound/pci/snd-fm801.ko
        vmlinux.o
  - the modules that use _PATCHKEY(id) indirectly to define other values
    include the header properly by including it indirectly through:
        include/uapi/linux/soundcard.h
    the #defines in that header file that use _PATCHKEY(id) are generated
    as KMI #define compile time constants to be tracked, the #defines are:
        WAVE_PATCH
        WAVEFRONT_PATCH
        SYSEX_PATCH
        MAUI_PATCH
        FM_PATCH
        OPL3_PATCH

sound/pci/echoaudio/echoaudio_dsp.h
  - defines many compile time #define constants, all of which related
    to interacting with various flavors of related echnoaudio hardware
  - this header file is used by these kernel modules:
        sound/pci/echoaudio/snd-darla20.ko
        sound/pci/echoaudio/snd-echo3g.ko
        sound/pci/echoaudio/snd-indigodjx.ko
        sound/pci/echoaudio/snd-mia.ko
        sound/pci/echoaudio/snd-indigoio.ko
        sound/pci/echoaudio/snd-gina20.ko
        sound/pci/echoaudio/snd-layla20.ko
        sound/pci/echoaudio/snd-indigodj.ko
        sound/pci/echoaudio/snd-mona.ko
        sound/pci/echoaudio/snd-indigo.ko
        sound/pci/echoaudio/snd-gina24.ko
        sound/pci/echoaudio/snd-darla24.ko
        sound/pci/echoaudio/snd-indigoiox.ko
        sound/pci/echoaudio/snd-layla24.ko

sound/pci/echoaudio/echoaudio.h
  - defines many compile time #define constants, all of which related
    to interacting with various flavors of related echnoaudio hardware
  - includes
        sound/pci/echoaudio/echoaudio_dsp.h
    which requires predefined constants (see above)
  - none of the #defines are related to a cross-module abi they are all
    related to hardware access

include/linux/wimax/debug.h
  - this header requires the code that includes it to define some values
    prior to including it, it is debug support that gets expanded into
    the .c files that include it
  - WiMAX is a long range wireless network, it is not wifi
  - few phones supported WiMAX, (2008-2010) in small markets
  - this technoglogy is not present in the mobile market (replaced by 4G
    and LTE)
  - in any case this header file defines debug infrastructure shared by 2
    drivers and some WiMAX network infrastructure in net/wimax, the debug
    information is not part of an ABI between those modules
  - modules:
        net/wimax/wimax.ko
        drivers/net/wimax/i2400m/i2400m-usb.ko
        drivers/net/wimax/i2400m/i2400m.ko

drivers/net/ethernet/chelsio/cxgb4/t4_pci_id_tbl.h
  - used to generated PCI ID tables for drivers which must define these:
        CH_PCI_DEVICE_ID_FUNCTION
        CH_PCI_ID_TABLE_ENTRY
    prior to including the header file
  - modules:
        drivers/net/ethernet/chelsio/cxgb4/cxgb4.ko.lka
        drivers/net/ethernet/chelsio/cxgb4vf/cxgb4vf.ko.lka
        drivers/scsi/csiostor/csiostor.ko.lka
  - there are no macros with arguments in this header

net/netfilter/ipset/ip_set_hash_gen.h
  - used to generated hashing code, must define these:
        MTYPE
        HTYPE
        HOST_MASK
    prior to including the header file
  - modules:
        net/netfilter/ipset/ip_set_hash_ipmark.ko
        net/netfilter/ipset/ip_set_hash_ipportip.ko
        net/netfilter/ipset/ip_set_hash_netport.ko
        net/netfilter/ipset/ip_set_hash_ip.ko
        net/netfilter/ipset/ip_set_hash_netportnet.ko
        net/netfilter/ipset/ip_set_hash_netiface.ko
        net/netfilter/ipset/ip_set_hash_mac.ko
        net/netfilter/ipset/ip_set_hash_ipmac.ko
        net/netfilter/ipset/ip_set_hash_ipportnet.ko
        net/netfilter/ipset/ip_set_hash_netnet.ko
        net/netfilter/ipset/ip_set_hash_net.ko
        net/netfilter/ipset/ip_set_hash_ipport.ko
  - the generated hashing code is templated from the code in the header file
  - the defines without arguments are not relevant to compile time define
    constants relevant to the AOSP GKI KMI, the data structures themselves
    and their underlying layouts are part of an inter-module AOSP GKI KMI
  - it is expected that all of these related modules would be recompiled
    and reshipped together in case this header file changes

include/trace/bpf_probe.h
include/trace/perf.h
include/trace/trace_events.h
  - These 3 headers are template like, they expect their callers to use
    them in special ways
  - They don't define compile time constants that might affect the AOSP
    GKI KMI
  - The 3 headers are used by these kernel components:
	block/kyber-iosched.ko
	drivers/ata/libata.ko
	drivers/block/nbd.ko
	drivers/fsi/fsi-core.ko
	drivers/fsi/fsi-master-ast-cf.ko
	drivers/fsi/fsi-master-gpio.ko
	drivers/gpu/drm/amd/amdgpu/amdgpu.ko
	drivers/gpu/drm/msm/msm.ko
	drivers/gpu/drm/radeon/radeon.ko
	drivers/gpu/drm/scheduler/gpu-sched.ko
	drivers/gpu/drm/tegra/tegra-drm.ko
	drivers/gpu/drm/v3d/v3d.ko
	drivers/gpu/drm/vc4/vc4.ko
	drivers/gpu/host1x/host1x.ko
	drivers/greybus/greybus.ko
	drivers/hid/intel-ish-hid/intel-ish-ipc.ko
	drivers/hwmon/hwmon.ko
	drivers/infiniband/core/ib_core.ko
	drivers/infiniband/core/ib_umad.ko
	drivers/lightnvm/pblk.ko
	drivers/md/bcache/bcache.ko
	drivers/media/platform/coda/coda-vpu.ko
	drivers/media/usb/pwc/pwc.ko
	drivers/mmc/core/mmc_core.ko
	drivers/mtd/devices/docg3.ko
	drivers/net/ethernet/freescale/dpaa/fsl_dpa.ko
	drivers/net/ethernet/freescale/dpaa2/fsl-dpaa2-eth.ko
	drivers/net/ethernet/intel/i40e/i40e.ko
	drivers/net/ethernet/intel/iavf/iavf.ko
	drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko
	drivers/net/ethernet/mellanox/mlxsw/mlxsw_spectrum.ko
	drivers/nvme/host/nvme-core.ko
	drivers/nvme/target/nvmet.ko
	drivers/scsi/scsi_transport_iscsi.ko
	drivers/siox/siox-core.ko
	drivers/staging/media/tegra-vde/tegra-vde.ko
	drivers/target/target_core_mod.ko
	drivers/usb/cdns3/cdns3.ko
	drivers/usb/dwc3/dwc3.ko
	drivers/usb/host/xhci-hcd.ko
	drivers/usb/mtu3/mtu3.ko
	drivers/usb/musb/musb_hdrc.ko
	fs/afs/kafs.ko
	fs/btrfs/btrfs.ko
	fs/cachefiles/cachefiles.ko
	fs/cifs/cifs.ko
	fs/erofs/erofs.ko
	fs/fscache/fscache.ko
	fs/gfs2/gfs2.ko
	fs/nfs/nfs.ko
	fs/nfs/nfsv4.ko
	fs/nfsd/nfsd.ko
	fs/nilfs2/nilfs2.ko
	fs/ocfs2/ocfs2.ko
	lib/objagg.ko
	net/9p/9pnet.ko
	net/batman-adv/batman-adv.ko
	net/dccp/dccp.ko
	net/ieee802154/ieee802154.ko
	net/ipv6/ipv6.ko
	net/mac802154/mac802154.ko
	net/rxrpc/rxrpc.ko
	net/sctp/sctp.ko
	net/sunrpc/auth_gss/auth_rpcgss.ko
	net/sunrpc/sunrpc.ko
	net/sunrpc/xprtrdma/rpcrdma.ko
	samples/trace_events/trace-events-sample.ko
	sound/firewire/motu/snd-firewire-motu.ko
	sound/firewire/snd-firewire-lib.ko
	sound/hda/snd-hda-core.ko
	sound/pci/hda/snd-hda-codec.ko
	sound/pci/hda/snd-hda-intel.ko
	vmlinux.o
