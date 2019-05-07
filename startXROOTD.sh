#!/bin/bash

######################################
startXRDserv_help () {
echo "This wrapper for starting of _xrootd_ services use the following _required_ variables defined in the configuration"
echo "__XRD_INSTANCE_NAME= name of the xrootd instance - required"
echo "__XRD_LOG= xrootd log file - required"
echo "__XRD_PIDFILE= xrootd pid file - required"
echo "__XRD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev50/xrd_config.htm#_Toc533023199"
}

######################################
getInstance_xrd () {
ps -o args= $(/usr/bin/pgrep -x xrootd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-n") {print $(x+1)} }}' #'
}

######################################
local CFG="${1}"
shift
[[ -z "${1}" ]] && { echo "the xrootd configuration file is needed as argument!!"; exit 1; }
ARGS="${@}"

## get __XRD_ server arguments from config file.
eval "$(sed -ne 's/\#@@/local /gp;' ${CFG})"

## make sure that they are defined
# shellcheck disable=2153
[[ -z "${__XRD_INSTANCE_NAME}"  || -z "${__XRD_LOG}"  || -z "${__XRD_PIDFILE}" ]]  && { startXRDserv_help; exit 1; }

## make sure that no services with the same instance name are started
xrd_instances=$(getInstance_xrd)
[[ ${xrd_instances} =~ ${__XRD_INSTANCE_NAME} ]] && { echo "startXROOTD :: >>>>>> FOUND XROOTD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }

## not matter how is enabled the debug mode means -d
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

exec xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${__XRD_LOG} -s ${__XRD_PIDFILE} -c ${CFG} ${ARGS}

