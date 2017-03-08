#!/bin/bash

######################################
startCMSDserv_help () {
echo "This wrapper for starting of Xrootd services use the following _required_ variables defined in the configuration"
echo "__CMSD_INSTANCE_NAME= name of the cmsd instance - required"
echo "__CMSD_LOG= cmsd log file - required"
echo "__CMSD_PIDFILE= cmsd pid file - required"
echo "__CMSD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev44/xrd_config.htm#_Toc454222279"
}

######################################
startCMSDserv () {

CFG="$1"

## get __XRD_ server arguments from config file. (are ignored by the actual xrd/cmsd)
eval $(sed -ne '/__CMSD_/p' ${CFG})

## make sure that they are defined
[[ -z "${__CMSD_INSTANCE_NAME}" || -z "${__CMSD_LOG}" || -z "${__CMSD_PIDFILE}" ]] && { startCMSDserv_help; exit 1;}

## not matter how is enabled the debug mode means -d
[[ -n "${__CMSD_DEBUG}" ]] && __XRD_DEBUG="-d"

local CMSD_START="/usr/bin/cmsd -b ${__XRD_DEBUG} -n ${__CMSD_INSTANCE_NAME} -l ${__CMSD_LOG} -s ${__CMSD_PIDFILE} -c ${CFG}"

echo eval ${CMSD_START}
}

startCMSDserv "$@"

