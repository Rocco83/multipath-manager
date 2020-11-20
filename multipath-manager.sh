#!/bin/bash
set -e

# packages needed lsscsi, sysfsutils
LSSCSI=$(type -P lsscsi) || { echo "lsscsi command is needed, please install package lsscsi"; exit 1; }
SYSTOOL=$(type -P systool) || { echo "systool command is needed, please installl sysfsutils package"; exit 1; }


# disks management for multipath, based on wwn of the storage
if [[ $# -ne 2 ]] ; then
    echo -e "$0 syntax: action wwn|all\n  action: scan|show|disable|enable|delete\n  wwn format: 0x000000000000000)\n  note: to delete a disk this must be disabled in advance\n  all will perform the action on all the devices (currently available only for scan)"
    exit 1
fi

ACTION=$1
WWID=$2

# wwid sanity check
[[ "${WWID}" =~ ^0x[[:xdigit:]]{16}$ ]] || [[ "${WWID}" == "all" ]] || { echo "WWN format is not correct"; exit 1; }

# if "all" is defined, only scan action is available
# other actions will not be defined in this section
if [[ "${WWID}" == "all" ]] ; then
    case ${ACTION} in
    "scan")
        SCSI_HOSTS=$(systool -c fc_transport | grep "^ *Device = " | sed -e 's/.*"target\([[:xdigit:]]*\):.*/\1/' | sort | uniq)
        for SCSI_HOST in ${SCSI_HOSTS} ; do
            echo "rescanning SCSI HOST ${SCSI_HOST}"
            echo "- - -" > /sys/class/scsi_host/host${SCSI_HOST}/scan
        done
        # don't proceed with other activities
        exit 0
        ;;
    esac
fi

# port_name is the WWN seen on the Storage side
# the target is showing the LUN seen on the OS
LUN="$(systool -c fc_transport -v | grep "port_name.*${WWID}" -A 1 -B 4 | grep "Device path" | sed 's/.*target\([0-9:]*\).*/\1/')"

# lun sanity check
if [[ "${LUN}" == "" ]] ; then
    echo "LUN has been not defined"
    exit 1
fi

# extract all the disks out from the multipath
DISKS=$(lsscsi | grep -e "^\[${LUN}:[[:digit:]]\]" | sed -e "s,.*/dev/,,")

# main switch-case
case ${ACTION} in
"show")
    echo "$DISKS"
    ;;
"enable")
    for disk in ${DISKS} ; do
        echo -n "enabling disk ${disk}: "
        multipathd -k"reinstate path ${disk}"
    done
    ;;
"disable")
    for disk in ${DISKS} ; do
        echo -n "disabling disk ${disk}: "
        multipathd -k"fail path ${disk}"
    done
    ;;
"delete")
    for disk in ${DISKS} ; do
        # If the disk is not failed in multipath, don't proceed (security failsafe)
        multipath -ll | grep -q "${LUN}:.*${disk}.*failed" || { echo "The disk $disk has been not marked as failed"; continue; }
        # the disk is maked as failed, deleting the disk
        echo -n "deleting disk ${disk}: "
        echo 1 > /sys/block/${disk}/device/delete
        if [[ -b /dev/${disk} ]] ; then
            echo "ko"
        else
            echo "ok"
        fi
    done
    ;;
"scan")
    echo "scan action is supported only with all targets"
    exit 1
    ;;
*)
    echo "the action '${ACTION}' specified is wrong"
    ;;
esac

exit 0
