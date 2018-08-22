#!/bin/bash

## formatters
BOOTUP=color
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

######################################
echo_success () {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "[  "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_SUCCESS
  echo -n $"OK"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "  ]"
  echo -ne "\\r"
  return 0
}

######################################
echo_failure () {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "[  "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
  echo -n $"DOWN"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "  ]"
  echo -ne "\\r"
  return 1
}

######################################
echo_passed () {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "["
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo -n $"PASSED"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "]"
  echo -ne "\\r"
  return 0
}

######################################
getPidFiles_xrd () {
ps -o args= $(/usr/bin/pgrep -x xrootd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-s") {print $(x+1)} }}' #'
}

######################################
getPidFiles_cmsd () {
ps -o args= $(/usr/bin/pgrep -x cmsd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-s") {print $(x+1)} }}' #'
}

######################################
getInstance_xrd () {
ps -o args= $(/usr/bin/pgrep -x xrootd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-n") {print $(x+1)} }}' #'
}

######################################
getInstance_cmsd () {
ps -o args= $(/usr/bin/pgrep -x cmsd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-n") {print $(x+1)} }}' #'
}

######################################
startXRDserv_help () {
echo "This wrapper for starting of _xrootd_ services use the following _required_ variables defined in the configuration"
echo "__XRD_INSTANCE_NAME= name of the xrootd instance - required"
echo "__XRD_LOG= xrootd log file - required"
echo "__XRD_PIDFILE= xrootd pid file - required"
echo "__XRD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev44/xrd_config.htm#_Toc454222279"
}

######################################
startCMSDserv_help () {
echo "This wrapper for starting of _cmsd_ services use the following _required_ variables defined in the configuration"
echo "__CMSD_INSTANCE_NAME= name of the cmsd instance - required"
echo "__CMSD_LOG= cmsd log file - required"
echo "__CMSD_PIDFILE= cmsd pid file - required"
echo "__CMSD_DEBUG= if defined enable debug mode - optional"
echo "for detailed explanation of arguments taken by xrd and cmsd see:"
echo "http://xrootd.org/doc/dev44/xrd_config.htm#_Toc454222279"
}

######################################
checkstate () {
echo "******************************************"
date
echo "******************************************"

local xrd_pid cmsd_pid returnval
returnval=0

xrd_pid=$(/usr/bin/pgrep -u "${USER}" xrootd | sed ':a;N;$!ba;s/\n/ /g');
cmsd_pid=$(/usr/bin/pgrep -u "${USER}" cmsd  | sed ':a;N;$!ba;s/\n/ /g');

# if pids not found show error
[[ -z "${cmsd_pid}" ]] && { echo -n "CMSD pid not found"; echo_failure; echo; returnval=1; }
[[ -z "${xrd_pid}" ]] && { echo -n "XROOTD pid not found"; echo_failure; echo; returnval=1; }

# if pids not found just return with error
[[ "${returnval}" == "1" ]] && return "${returnval}";

echo -ne "CMSD pid :\t${cmsd_pid}"; echo_success; echo
echo -ne "XROOTD pid :\t${xrd_pid}"; echo_success; echo

return "${returnval}"
}

######################################
startXROOTDprocs () {
local CFG="$1"

## get __CMSD_ server arguments from config file.
eval "$(sed -ne 's/\#@@/local /gp;' ${CFG})"

local cmsd_needed=$( grep 'all.role' ${CFG}) )

if [[ -n "${cmsd_needed}" ]]; then
  ## make sure that they are defined
  # shellcheck disable=2153
  [[ -z "${__CMSD_INSTANCE_NAME}" || -z "${__CMSD_LOG}" || -z "${__CMSD_PIDFILE}" ]] && { startCMSDserv_help; exit 1; }

  ## not matter how is enabled the debug mode means -d
  [[ -n "${__CMSD_DEBUG}" ]] && __CMSD_DEBUG="-d"

  ## create the command lines
  local CMSD_START="/usr/bin/cmsd -b ${__CMSD_DEBUG} -n ${__CMSD_INSTANCE_NAME} -l ${__CMSD_LOG} -s ${__CMSD_PIDFILE} -c ${CFG}"

  ## make sure that no services with the same instance name are started
  local cmsd_instances=$(getInstance_cmsd)
  [[ ${cmsd_instances} =~ ${__CMSD_INSTANCE_NAME} ]] && { echo "startXROOTDprocs :: >>>>>> FOUND CMSD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }

  ## start services
  eval "${CMSD_START}"
fi

## make sure that they are defined
# shellcheck disable=2153
[[ -z "${__XRD_INSTANCE_NAME}"  || -z "${__XRD_LOG}"  || -z "${__XRD_PIDFILE}" ]]  && { startXRDserv_help; exit 1; }

## not matter how is enabled the debug mode means -d
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

## create the command lines
local XRD_START="/usr/bin/xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${__XRD_LOG} -s ${__XRD_PIDFILE} -c ${CFG}"

## make sure that no services with the same instance name are started
local xrd_instances=$(getInstance_xrd)
[[ ${xrd_instances} =~ ${__XRD_INSTANCE_NAME} ]] && { echo "startXROOTDprocs :: >>>>>> FOUND XROOTD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }

## start services
eval "${XRD_START}"
}

[[ -z "${1}" ]] && { echo "the xrootd configuration file is needed as argument!!"; exit 1; }

startXROOTDprocs "${1}"
checkstate

