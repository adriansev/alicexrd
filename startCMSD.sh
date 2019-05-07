#!/bin/bash

######################################
startCMSDserv_help () {
echo "This wrapper for starting of _cmsd_ services use the following _required_ variables defined in the configuration"
echo "__CMSD_INSTANCE_NAME= name of the cmsd instance - required"
echo "__CMSD_LOG= cmsd log file - required"
echo "__CMSD_PIDFILE= cmsd pid file - required"
echo "__CMSD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev49/cms_config.htm#_Toc520504646"
}

######################################
getInstance_cmsd () {
ps -o args= $(/usr/bin/pgrep -x cmsd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-n") {print $(x+1)} }}' #'
}

######################################
local CFG="${1}"
shift
[[ -z "${1}" ]] && { echo "the xrootd configuration file is needed as argument!!"; exit 1; }
ARGS="${@}"

## get __CMSD_ server arguments from config file.
eval "$(sed -ne 's/\#@@/local /gp;' ${CFG})"

## make sure that they are defined
# shellcheck disable=2153
[[ -z "${__CMSD_INSTANCE_NAME}" || -z "${__CMSD_LOG}" || -z "${__CMSD_PIDFILE}" ]] && { startCMSDserv_help; exit 1; }

## make sure that no services with the same instance name are started
cmsd_instances=$(getInstance_cmsd)
[[ ${cmsd_instances} =~ ${__CMSD_INSTANCE_NAME} ]] && { echo "startCMSD :: >>>>>> FOUND CMSD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }

## not matter how is enabled the debug mode means -d
[[ -n "${__CMSD_DEBUG}" ]] && __CMSD_DEBUG="-d"

exec cmsd -b ${__CMSD_DEBUG} -n ${__CMSD_INSTANCE_NAME} -l ${__CMSD_LOG} -s ${__CMSD_PIDFILE} -c ${CFG} ${ARGS}

