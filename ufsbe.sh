#! /bin/sh

# Copyright (c) 2021 Slawomir Wojciech Wojtczak (vermaden)
# All rights reserved.
#
# THIS SOFTWARE USES FREEBSD LICENSE (ALSO KNOWN AS 2-CLAUSE BSD LICENSE)
# https://www.freebsd.org/copyright/freebsd-license.html
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that following conditions are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS 'AS IS' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# ------------------------------
# UFS BOOT ENVIRONMENTS MANAGER
# ------------------------------
# vermaden [AT] interia [DOT] pl
# https://vermaden.wordpress.com

# SETTINGS
NAME=${0##*/}
PREFIX='ufsbe'
MNTDIR='/ufsbe'
FORMAT="%-8s %-12s %-4s\n"

# DISPLAY VERSION
if [ "${1}" = "--version" -o \
     "${1}" =  "-version" -o \
     "${1}" =   "version" ]
then
  echo "            _____   ___         _  ____ __   "
  echo "         __/  __/  /  /        / //    \\\ \  "
  echo "    __ _/_   _/___/  /  ____  / //  /  / \ \ "
  echo "   /  /  /  / ___/    \/  _ \/ / \     \ / / "
  echo "  /  /  /  /\__ \  /  /  ___/\ \ /  /  // /  "
  echo "  \____/__/\____/____/\____/  \_\\\____//_/   "
  echo
  echo "${NAME} 0.1 2021/04/01"
  echo
  exit 0
fi

# CHECK USER WITH whoami(1)
if [ "$( whoami )" != "root" ]
then
  echo "NOPE: you need to be 'root' to use that tool"
  exit 1
fi

# DISPLAY SIMPLE USAGE MESSAGE
__usage() {
  cat << BSD
usage:
  ${NAME} (l)ist
  ${NAME} (a)ctivate
  ${NAME} (s)ync <source> <target>

BSD
  exit 1
}

# GET CURRENT ROOT DEV FROM mount(8) OUTPUT
__get_root_dev() {
  local MOUNT=$( mount | grep ' / ' | awk '{print $1}' )
  local MOUNT=$( basename "${MOUNT}" )
  echo ${MOUNT}
}

# SET NEEDED GLOBAL VARIABLES USED MANY TIMES BY FUNCTIONS
__global_variables() {
  MOUNT=$( __get_root_dev )
  ROOTDEV=$( echo "${MOUNT}" | grep -o -E '^[a-z]+[0-9]+' | head -1 )
  GPART_SHOW_ROOTDEV=$( gpart show -p -l "${ROOTDEV}" 2> /dev/null | grep "${PREFIX}/" )
}

# SETUP HELP - 0 DEVICES MEANS YOU NEED TO SETUP PARTITIONS WITH LABELS
__setup() {
  if [ "${GPART_SHOW_ROOTDEV}" = "" ]
  then
    echo
    echo "NOPE: did not found boot environment setup with '${PREFIX}' label"
    echo
    echo "INFO: setup each boot environment partition with appropriate label"
    echo
    echo "HELP: list all 'freebsd-ufs' partitions type:"
    echo
    echo "  # gpart show -p | grep freebsd-ufs"
    echo "      2098216   33554432  ada0p3  freebsd-ufs  [bootme]  (16G)"
    echo "     35652648   33554432  ada0p4  freebsd-ufs  (16G)"
    echo "     69207080   33554432  ada0p5  freebsd-ufs  (16G)"
    echo
    echo "HELP: to setup partitions 3/4/5 as boot environments type:"
    echo
    echo "  # gpart modify -i 3 -l ufsbe/3 ada0"
    echo "  # gpart modify -i 4 -l ufsbe/4 ada0"
    echo "  # gpart modify -i 5 -l ufsbe/5 ada0"
    echo
    exit 1
  fi
}

# SET bootme ON CURRENT DEV MOUNTED AS /
__set_bootme_root() {
  local MOUNT=$( __get_root_dev )
  local MOUNT=$( echo "${MOUNT}" | grep -o -E '^[a-z]+[0-9]+p[0-9]+' | head -1 )
  if [ "${MOUNT}" = "" ]
  then
    echo "NOPE: only GPT partitioning is supported"
    exit 1
  fi
  local PART=$( echo "${MOUNT}" | grep -E -o '[0-9]+$' )
  gpart set -a bootme -i ${PART} ${ROOTDEV} 1> /dev/null 2> /dev/null
  if [ ${?} -ne 0 ]
  then
    echo "NOPE: failed to set 'bootme' flag on / filesystem"
    exit 1
  else
    echo "INFO: flag 'bootme' succesfully set on / filesystem"
  fi
}

# CHECK IF bootme FLAG IS SET ANYWHERE
__bootme_must_be_set_once() {
  if gpart show "${ROOTDEV}" | grep -q bootme 1> /dev/null 2> /dev/null
  then
    # THE bootme FLAG IS SET
    # THE bootme FLAG MUST BE SET ONLY ONCE
    local COUNT=$( echo "${GPART_SHOW_ROOTDEV}" | grep -c bootme )
    if [ ${COUNT} -ne 1 ]
    then
      # IF bootme SET MORE THEN ONCE THEN SET ON CURRENT /
      echo "${GPART_SHOW_ROOTDEV}" \
        | grep bootme \
        | grep -v ${MOUNT} \
        | while read BEGIN END PROVIDER LABEL OPTIONS
          do
            local PART=$( echo ${PROVIDER} | grep -E -o '[0-9]+$' )
            gpart unset -a bootme -i ${PART} ${ROOTDEV} 1> /dev/null 2> /dev/null
            unset PART
          done
      __set_bootme_root
    fi
  else
    # THE bootme FLAG IS NOT SET
    # THEN SET bootme ON CURRENT /
    __set_bootme_root
  fi
}

# CHECK IF LABEL FOR BOOT ENVIRONMENT EXISTS
__check_label_exists() { # 1=LABEL
  local BENAME=$( echo "${GPART_SHOW_ROOTDEV}" | grep "${PREFIX}/${1}" )
  if [ "${BENAME}" = "" ]
  then
    echo "NOPE: boot environmnt '${1}' does not exists"
    exit 1
  fi
}

# CHECK IF BOOT ENVIRONMENT IS ALREADY ACTIVE
__check_already_active() {
  local NEW=$( echo "${GPART_SHOW_ROOTDEV}" | grep "${PREFIX}/${1}" | grep bootme )
  if [ "${NEW}" != "" ]
  then
    echo "INFO: boot environment '${1}' is already active"
    exit 1
  fi
}

# REMOVES bootme FLAG FROM ALL PARTITIONS
__bootme_unset_all() {
  echo "${GPART_SHOW_ROOTDEV}" \
    | grep "${PREFIX}/" \
    | while read BEGIN END PROVIDER LABEL OPTIONS
      do
        local PART=$( echo ${PROVIDER} | grep -o -E '[0-9]+$' )
        gpart unset -a bootme -i ${PART} ${ROOTDEV} 1> /dev/null 2> /dev/null
        unset PART
      done
}

# SETS bootme FLAG ON SELECTED PARTITION
__bootme_set() { # 1=LABEL_AFTER_PREFIX
  echo "${GPART_SHOW_ROOTDEV}" \
    | grep "${PREFIX}/${1}" \
    | while read BEGIN END PROVIDER LABEL OPTIONS
      do
        local UFSBE_PART=$( echo ${PROVIDER} | grep -o -E '[0-9]+$' )
        gpart set -a bootme -i ${UFSBE_PART} ${ROOTDEV} 1> /dev/null 2> /dev/null
        unset PART
      done
  local NEW=$( echo "${GPART_SHOW_ROOTDEV}" | grep "${PREFIX}/${1}" )
  if [ "${NEW}" = "" ]
  then
    echo "NOPE: failed to activate '${1}' as new boot environment"
    exit 1
  fi
}

# CHECK IF SPECIFIED DISK IS MOUNTED AND TRY TO mount(8) IT IF ITS NOT
__check_disk_mounted() { # 1=DISK
  local MOUNT_UFS=$( mount -t ufs -p )
  if ! echo "${MOUNT_UFS}" | grep -q "^/dev/${1}"
  then
    mount /dev/${1}
    if [ ${?} -ne 0 ]
    then
      echo "NOPE: disk '/dev/${1}' can not be mounted"
      exit 1
    fi
  fi
}

# GENERATES NEEDED fstab(5) FILES AND DIRECTORIES FOR MOUNTING
__fstab_generate() {
  local UFSBE_DISKS=$( echo "${GPART_SHOW_ROOTDEV}" | awk '{print $3}' )
  local MOUNT_UFS=$( mount -t ufs -p )
  echo "${UFSBE_DISKS}" \
    | while read DISK
      do
        local DISK_MNT=$( echo "${MOUNT_UFS}" | grep ${DISK} | awk '{print $2}' )
        __check_disk_mounted ${DISK}
        if [ "${DISK_MNT}" = "/" ]
        then
          local FSTAB_PREFIX=""
        else
          local FSTAB_PREFIX="${DISK_MNT}"
        fi
        echo "${MOUNT_UFS}" \
          | while read DEVICE MNTPNT FS OPTS DUMP PASS
            do
              local DEVSHORT=$( basename ${DEVICE} )
              local MNT_NAME=$( echo "${GPART_SHOW_ROOTDEV}" \
                                  | grep ${DEVSHORT} \
                                  | awk '{print $4}' \
                                  | awk -F '/' '{print $NF}' )
              mkdir -p ${MNTDIR}/${MNT_NAME}
              mkdir -p ${MNTDIR}/${MNT_NAME}/${MNTDIR}/${MNT_NAME}
              mkdir -p ${DISK_MNT}/${MNTDIR}/${MNT_NAME}
              if [ ${DEVSHORT} = ${DISK} ]
              then
                if [ -f ${FSTAB_PREFIX}/etc/fstab ]
                then
                  sed \
                    -i '' \
                    -E "s|^${DEVICE}.*|${DEVICE} / ${FS} ${OPTS} ${DUMP} ${PASS}|g" \
                    ${FSTAB_PREFIX}/etc/fstab
                fi
              else
                if [ -f ${FSTAB_PREFIX}/etc/fstab ]
                then
                  sed \
                    -i '' \
                    -E "s|^${DEVICE}.*|${DEVICE} ${MNTDIR}/${MNT_NAME} ${FS} ${OPTS} ${DUMP} ${PASS}|g" \
                    ${FSTAB_PREFIX}/etc/fstab
                fi
              fi
            done
      done
}

# LISTS ALL BOOT ENVIRONMENTS
__list_envs() {
  printf "${FORMAT}" PROVIDER LABEL ACTIVE
  echo "${GPART_SHOW_ROOTDEV}" \
    | grep "${PREFIX}/" \
    | while read BEGIN END PROVIDER LABEL OPTIONS
      do
        local FLAGS=""
        if [ ${MOUNT} = ${PROVIDER} ]
        then
          local FLAGS="${FLAGS}N"
        fi
        OPTIONS=$( echo ${OPTIONS} | tr -d '[]()0-9.KMGT' )
        if echo "${OPTIONS}" | grep -q bootme 1> /dev/null 2> /dev/null
        then
          local FLAGS="${FLAGS}R"
        fi
        if [ "${FLAGS}" = "" ]
        then
          local FLAGS="-"
        fi
        printf "${FORMAT}" ${PROVIDER} ${LABEL} ${FLAGS}
        unset FLAGS
      done
}

# CHECKS IF BOOT ENVIRONMENT IS POPULATED OR EMPTY
__check_empty_be() { # 1=LABEL
  echo "${GPART_SHOW_ROOTDEV}" \
    | grep "${PREFIX}/${1}" \
    | while read BEGIN END PROVIDER LABEL OPTIONS
      do
        local MNT_POINT=$( mount -t ufs -p | grep ${PROVIDER} | awk '{print $2}' )
        for FILE in ${MNT_POINT}/boot/kernel/kernel \
                    ${MNT_POINT}/boot/loader.conf \
                    ${MNT_POINT}/etc/rc.conf \
                    ${MNT_POINT}/rescue/ls \
                    ${MNT_POINT}/bin/ls \
                    ${MNT_POINT}/sbin/fsck \
                    ${MNT_POINT}/usr/bin/su \
                    ${MNT_POINT}/usr/sbin/chroot \
                    ${MNT_POINT}/lib/libc.so.* \
                    ${MNT_POINT}/usr/lib/libpam.so.*
        do
          if ! ls ${FILE} 1> /dev/null 2> /dev/null
          then
            echo "NOPE: boot environment '${1}' is not complete"
            echo "INFO: critical file '${FILE}' is missing"
            echo "INFO: use 'sync' option or copy file manually"
            exit 1
          fi
        done
      done
}

# ACTIVATES SPECIFIED BOOT ENVIRONMENT
__activate() { # 1=LABEL
  __check_label_exists ${1}
  __check_empty_be ${1}
  __check_already_active ${1}
  __bootme_unset_all
  __bootme_set ${1}
  __fstab_generate
  echo "INFO: boot environment '${1}' now activated"
}

# ADDS SLASH AT THE END OF DIRECTORY PATH
__add_slash() {
  [ $( echo "${@}" | grep -o -E ".$" ) = / ] && echo "${@}" || echo "${@}/"
}

# SYNCS <SOURCE> WITH <RARGET> USING rsync(1) COMMAND
__sync() { # 1=SOURCE 2=TARGET
  unset rsync
  if ! which -s rsync
  then
    echo "NOPE: rsync(1) is not available in \${PATH}"
    echo "INFO: install 'net/rsync' package or port"
    exit 1
  fi
  local DISK_SOURCE=$( echo "${GPART_SHOW_ROOTDEV}" | grep ${PREFIX}/${1} | awk '{print $3}' )
  local DISK_TARGET=$( echo "${GPART_SHOW_ROOTDEV}" | grep ${PREFIX}/${2} | awk '{print $3}' )
  __check_disk_mounted ${DISK_SOURCE}
  __check_disk_mounted ${DISK_TARGET}
  local MOUNT_UFS=$( mount -t ufs -p )
  local MNT_SOURCE=$( echo "${MOUNT_UFS}" | grep ${DISK_SOURCE} | awk '{print $2}' )
  local MNT_TARGET=$( echo "${MOUNT_UFS}" | grep ${DISK_TARGET} | awk '{print $2}' )
  unset MOUNT_UFS
  rsync \
    -aHXAEUxSK \
    --open-noatime \
    --delete-before \
    --copy-unsafe-links \
    $( __add_slash ${MNT_SOURCE} ) \
    $( __add_slash ${MNT_TARGET} ) \
    1> /dev/null 2> /dev/null
  echo "INFO: boot environments '${1}' (source) => '${2}' (target) synced"
}

# MAIN()
__global_variables
__setup
__bootme_must_be_set_once

# OPTIONS
case ${1} in
  (l|list)
    __list_envs
    ;;

  (a|activate)
    if [ "${2}" != "" ]
    then
      __activate "${2}"
    else
      __usage
    fi
    ;;

  (s|sync)
    if [ "${2}" != "" -a "${3}" != "" ]
    then
      __sync ${2} ${3}
    else
      __usage
    fi
    ;;

  (*)
    __usage
    ;;

esac
