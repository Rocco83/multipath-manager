#!/bin/bash
# Written by Daniele Palumbo <daniele _at_ retaggio _dot_ net>
# This script is relesed under GPLv3
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
[[ "${WWID}" =~ ^0x[[:xdigit:]]{16}$ ]] || [[ "${WWID}" =~ ^[[:xdigit:]:]{23}$ ]] || [[ "${WWID}" == "all" ]] || { echo "WWN format is not correct"; exit 1; }

# converting WWID to 0x format
if [[ "${WWID}" =~ ^[[:xdigit:]:]{23}$ ]] ; then
    WWID="0x$(echo $WWID | sed -s 's/://g')"
fi

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
        # don't proceed with other actions
        exit 0
        ;;
    *)
        echo "Action '${ACTION}' not supported with WWID = ALL"
        exit 1
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
DISKS=$(lsscsi | grep -E "^\[${LUN}:[[:digit:]]+\]" | sed -e "s,.*/dev/,,")

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
        multipath -ll | grep -q "${LUN}:.*${disk} .*failed" || { echo "The disk $disk has been not marked as failed"; continue; }
        # the disk is maked as failed, deleting the disk
        echo -n "deleting disk ${disk}: "
        echo 1 > /sys/block/${disk}/device/delete
        # waiting a little bit before doing the check
        sleep 0.2
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
