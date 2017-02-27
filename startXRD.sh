#!/bin/bash

help () {
echo "This wrapper for starting of Xrootd services use the following _required_ variables defined in the configuration"
echo "__XRD_INSTANCE_NAME= name of the xrootd instance - required"
echo "__XRD_LOG= log file - required"
echo "__XRD_PIDFILE= pid file - required"
echo "__XRD_DEBUG= if defined enable debug mode - optional"

echo "for details : http://xrootd.org/doc/dev44/xrd_config.htm#_Toc454222279"
}

filename () {
local filename="${1##*/}"
local extension="${1##*.}"
echo "${filename%.*}" "${extension}"
}

CFG="$1"

## get __XRD_ server arguments from config file. (are ignored by the actual xrd/cmsd)
eval $(sed -ne '/__XRD_/p' ${CFG})

## make sure that they are defined
[[ -z "${__XRD_INSTANCE_NAME}" || -z "${__XRD_LOG}" || -z "${__XRD_PIDFILE}" ]] && { help; exit 1;}

## not matter how is enabled the debug mode means -d
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

## in order to make distinction between xrd and cmsd for log and pid file we add _xrd/_cmsd just before the extension
arr_log=($(filename "${__XRD_LOG}"))
arr_pid=($(filename "${__XRD_PIDFILE}"))

XRD_LOG="$(dirname "${__XRD_LOG}")/${arr_log[0]}_xrd.${arr_log[1]}"
CMSD_LOG="$(dirname "${__XRD_LOG}")/${arr_log[0]}_cmsd.${arr_log[1]}"

XRD_PID="$(dirname "${__XRD_PIDFILE}")/${arr_pid[0]}_xrd.${arr_pid[1]}"
CMSD_PID="$(dirname "${__XRD_PIDFILE}")/${arr_pid[0]}_cmsd.${arr_pid[1]}"

XRD_START="/usr/bin/xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${XRD_LOG} -s ${XRD_PID} -c ${CFG}"
CMSD_START="/usr/bin/cmsd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${CMSD_LOG} -s ${CMSD_PID} -c ${CFG}"

echo ${XRD_START}
echo ${CMSD_START}

