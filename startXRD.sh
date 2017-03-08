#!/bin/bash

######################################
startXRDserv_help () {
echo "This wrapper for starting of Xrootd services use the following _required_ variables defined in the configuration"
echo "__XRD_INSTANCE_NAME= name of the xrootd instance - required"
echo "__XRD_LOG= xrootd log file - required"
echo "__XRD_PIDFILE= xrootd pid file - required"
echo "__XRD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev44/xrd_config.htm#_Toc454222279"
}

######################################
startXRDserv () {
local CFG="$1"

## get __XRD_ server arguments from config file. (are ignored by the actual xrd/cmsd)
eval $(sed -ne '/__XRD_/p' ${CFG})

## make sure that they are defined
[[ -z "${__XRD_INSTANCE_NAME}" || -z "${__XRD_LOG}" || -z "${__XRD_PIDFILE}" ]] && { startXRDserv_help; exit 1;}

## not matter how is enabled the debug mode means -d
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

local XRD_START="/usr/bin/xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${__XRD_LOG} -s ${__XRD_PIDFILE} -c ${CFG}"

echo eval ${XRD_START}
}

startXRDserv "$@"


