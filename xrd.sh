#!/bin/bash

## formatters
BOOTUP=color
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

CURLCMD="/usr/bin/curl -m 1 -fsSLk"

######################################
check_prerequisites() {
[ ! -e "/usr/bin/curl" ] && { echo "curl command not found; do : yum -y install curl.x86_64"; exit 1; }
[ ! -e "/usr/bin/bzip2" ] && { echo "bzip2 command not found (logs compression); do : yum -y install bzip2.x86_64"; exit 1; }
}

##########  FUNCTIONS   #############
echo_success() {
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
echo_failure() {
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
echo_passed() {
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
get_name_extension () {
local filename="${1##*/}"
local extension="${1##*.}"
echo "${filename%.*}" "${extension}"
}

######################################
cfg_set_value () {
local CFGFILE="$1"
local KEY="$2"
local VALUE="$3"
sed --follow-symlinks -i "s#^\($KEY\s*=\s*\).*\$#\1\"$VALUE\"#" ${CFGFILE}
}

######################################
cfg_set_xrdvalue () {
local CFGFILE="$1"
local KEY="$2"
local VALUE="$3"
sed --follow-symlinks -i "s#^\#@@\($KEY\s*=\s*\).*\$#\#@@\1\"$VALUE\"#" ${CFGFILE}
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
startXROOTDprocs () {
local CFG="$1"

## get __CMSD_ server arguments from config file.
eval "$(sed -ne 's/\#@@/local /gp;' ${CFG})"

## make sure that they are defined
# shellcheck disable=2153
[[ -z "${__CMSD_INSTANCE_NAME}" || -z "${__CMSD_LOG}" || -z "${__CMSD_PIDFILE}" ]] && { startCMSDserv_help; exit 1; }
[[ -z "${__XRD_INSTANCE_NAME}"  || -z "${__XRD_LOG}"  || -z "${__XRD_PIDFILE}" ]]  && { startXRDserv_help; exit 1; }


## not matter how is enabled the debug mode means -d
[[ -n "${__CMSD_DEBUG}" ]] && __CMSD_DEBUG="-d"
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

## create the command lines
local CMSD_START="/usr/bin/cmsd -b ${__CMSD_DEBUG} -n ${__CMSD_INSTANCE_NAME} -l ${__CMSD_LOG} -s ${__CMSD_PIDFILE} -c ${CFG}"
local XRD_START="/usr/bin/xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${__XRD_LOG} -s ${__XRD_PIDFILE} -c ${CFG}"

## make sure that no services with the same instance name are started
local cmsd_instances=$(getInstance_cmsd)
local xrd_instances=$(getInstance_xrd)

[[ ${cmsd_instances} =~ ${__CMSD_INSTANCE_NAME} ]] && { echo "startXROOTDprocs :: >>>>>> FOUND CMSD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }
[[ ${xrd_instances} =~ ${__XRD_INSTANCE_NAME} ]] && { echo "startXROOTDprocs :: >>>>>> FOUND XROOTD SERVICE WITH THE SAME INSTANCE NAME! <<<<<<<"; exit 1; }

## start services
eval "${CMSD_START}"
eval "${XRD_START}"
}

######################################
getLocations () {
# Define system settings
# Find configs, dirs, xrduser, ...

## find the location of xrd.sh script
SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SOURCE}" ]; do ## resolve $SOURCE until the file is no longer a symlink
  XRDSHDIR="$( cd -P "$(dirname "${SOURCE}" )" && pwd )" ##"
  SOURCE="$(readlink "${SOURCE}")" ##"
  [[ "${SOURCE}" != /* ]] && SOURCE="${XRDSHDIR}/${SOURCE}" ## if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

XRDSHDIR="$(cd -P "$( dirname "${SOURCE}" )" && pwd)" ##"
export XRDSHDIR

# location of logs, admin, core dirs
XRDRUNDIR=${XRDRUNDIR:-${XRDSHDIR}/run/}
export XRDRUNDIR

# location of configuration files; does not need to be in the same location with xrd.sh
XRDCONFDIR=${XRDCONFDIR:-${XRDSHDIR}/xrootd.conf/}
export XRDCONFDIR

## LOCATIONS AND INFORMATIONS
XRDCONF=${XRDCONF:-${XRDCONFDIR}/system.cnf}
export XRDCONF

if [[ -e "${XRDCONF}" && -f "${XRDCONF}" ]]; then
  # shellcheck source=/dev/null
  source "${XRDCONF}";
else
  echo "Could not find main conf file ${XRDCONF}";
  exit 1;
fi

## Locations and user settings
USER=${USER:-$LOGNAME}
[[ -z "${USER}" ]] && USER=$(/usr/bin/id -nu)
SCRIPTUSER="${USER}"

## automatically asume that the owner of location of xrd.sh is XRDUSER
XRDUSER=$(/usr/bin/stat -c %U "${XRDSHDIR}/xrd.sh")
export XRDUSER

## protect the case when some other user start xrd.sh; make sure the xrd.sh is owned by the user that will run xrootd
[[ "${SCRIPTUSER}" != "${XRDUSER}" ]] && { echo "User running the xrd.sh and the owner of xrd.sh are different! To protect against problems use the same user as xrd.sh"; exit 1; }

# make sure xrd.sh is executable by user and user group
/bin/chmod ug+x "${XRDSHDIR}/xrd.sh"

## get the home dir of the designated xrd user
XRDHOME=$(getent passwd "${XRDUSER}" | awk -F: '{print $(NF-1)}') #'
[[ -z "${XRDHOME}" ]] && { echo "Fatal: invalid home for user ${XRDUSER}"; exit 1;}
export XRDHOME

## LACALROOT defined in system.cnf; LOCALPATHPFX defined in MonaLisa
if [[ ! -e "${LOCALROOT}/${LOCALPATHPFX}" ]]; then
  echo "LOCALROOT/LOCALPATHPFX : ${LOCALROOT}/${LOCALPATHPFX} not found! Please create it as user: ${XRDUSER}!";
  exit 1;
fi

## Treatment of arguments
local FILE_NAME DIR_NAME EXT ARG1 ARG2
# default xrootd configuration template
XRDCF_TMP="${XRDCONFDIR}/xrootd.xrootd.cf.tmp"

ARG1="${1}"
ARG2="${2}"

# if XRD_DONOTRECONF is enabled then if argument is present it should be the XRDCF
if [[ -n "${XRD_DONOTRECONF}" ]]; then
  # if there is no explicit XRDCF then juts use the default name without .tmp extension
  if [[ -z "${ARG1}"  ]]; then
    DIR_NAME=$(/usr/bin/dirname "${XRDCF_TMP}")
    FILE_NAME=$(/bin/basename "${XRDCF_TMP}" .tmp)
    XRDCF="${DIR_NAME}/${FILE_NAME}"
  else
    # an argument was passed to getLocations function; we assume that is the name of xrootd configuration file
    [[ ! -e "${ARG1}" ]] && { echo "getLocations :: XRD_DONOTRECONF enabled :: configuration file >>> ${ARG1} <<< not found!!!"; exit 1; }
    XRDCF="${ARG1}"
  fi

  # we reset the default value of XRDCF_TMP to a warning message that should be visible at services start
  XRDCF_TMP=">>>   XRD_DONOTRECONF enabled   <<< template file not used!"
  export XRDCF_TMP XRDCF
  return 0;
fi

[[ -n "${ARG1}" ]] && XRDCF_TMP="${ARG1}"
[[ -n "${ARG2}" ]] && XRDCF="${ARG2}"

# check if template file is present - required
[[ ! -e "${XRDCF_TMP}" ]] && { echo "not found template file - ${XRDCF_TMP} "; exit 1; }

# if configuration file is not specified (ARG2) then remove the tmp extension from template and use that name
# even if no ARG1 is given the same procedure must be done for the default XRDCF_TMP
if [[ -z "${ARG2}" ]]; then
  FILE_NAME=$(/bin/basename "${XRDCF_TMP}")
  DIR_NAME=$(/usr/bin/dirname "${XRDCF_TMP}")

  EXT="${XRDCF_TMP##*.}"
  [[ "${EXT}" != "tmp" ]] && { echo "template file should have .tmp extension"; exit 1; }

  FILE_NAME=$(/bin/basename "${XRDCF_TMP}" .tmp)
  XRDCF="${DIR_NAME}/${FILE_NAME}"
fi

export XRDCF_TMP XRDCF

# core file size (blocks, -c); legacy directive
#ulimit -c unlimited
}

######################################
##  Get all relevant server information from MonaLisa
serverinfo () {
# if we are called by mistake (when XRD_DONOTRECONF is enabled) then just return
[[ -n "${XRD_DONOTRECONF}" ]] && return 0;

# if XRDCONF is not set (by getLocations) we must run it passing the serverinfo args to getLocations
# this is needed for customization of template and final xrootd configuration file
getLocations "$@"

# links to alimonitor to query about info
local ALIMON_SE_URL ALIMON_IP_URL
ALIMON_SE_URL='"http://alimonitor.cern.ch/services/se.jsp?se='"${SE_NAME}"'&ml_ip=true&resolve=true"' #'
ALIMON_IP_URL="http://alimonitor.cern.ch/services/ip.jsp"

## if SE_NAME not found in system.cnf
[[ -z "${SE_NAME}" ]] && { echo "SE name is not defined in system.cnf!" && exit 1; }

## Get SE info from MonaLisa and check if the SE name is valid; try 3 times before fail and exit
local SE_INFO

SE_INFO=$(eval "${CURLCMD}" "${ALIMON_SE_URL}";)
[[ -z "${SE_INFO}" ]] && { sleep 1; SE_INFO=$(eval "${CURLCMD}" "${ALIMON_SE_URL}";); }
[[ -z "${SE_INFO}" ]] && { sleep 2; SE_INFO=$(eval "${CURLCMD}" "${ALIMON_SE_URL}";); }
[[ "${SE_INFO}" == "null" ]] || [[ -z "${SE_INFO}" ]] && { echo "The stated SE name ${SE_NAME} is not found - either bad conectivity or wrong SE name"; exit 1; }

[[ -n "${XRDSH_DEBUG}" ]] && echo "Found SE_NAME=${SE_NAME}"

## Find information about site from ML
MONALISA_FQDN=$(/bin/awk -F": " '/MLSERVICE_/ {print $2}' <<< "${SE_INFO}" | head -n1) #'

## Validate the ip - make sure is a public one and the reverse match the defined hostname
# get my ip
local MYNET MYIP REVERSE

MYNET=$(eval "${CURLCMD}" "${ALIMON_IP_URL}")
[[ -z "${MYNET}" ]] && { sleep 1; MYNET=$(eval "${CURLCMD}" "${ALIMON_IP_URL}"); }
[[ -z "${MYNET}" ]] && { sleep 2; MYNET=$(eval "${CURLCMD}" "${ALIMON_IP_URL}"); }
[[ -z "${MYNET}" ]] && { echo "MYNET not found, maybe bad connectivity to alimonitor?" && exit 1; }

## Network information and validity checking
MYIP=$(/bin/awk '/IP/ {gsub("IP:","",$1); print $1;}'  <<< "${MYNET}") #'
REVERSE=$(/bin/awk '/FQDN/ {gsub("FQDN:","",$1); print $1;}'  <<< "${MYNET}" ) #'

## make sure the exit public ip is locally configured
local ip_list found_at
ip_list=$(/sbin/ip addr show scope global permanent up | /bin/awk '/inet/ {split ($2,ip,"/"); print ip[1];}') #'
found_at=$(expr index "${ip_list}" "${MYIP}")
[[ "${found_at}" == "0" ]] && { echo "Server without public/rutable ip. No NAT schema supported at this moment"; exit 1; }

## what is my local set hostname
local MYHNAME
MYHNAME=$(/bin/hostname -f)
[[ -z "${MYHNAME}" ]] && MYHNAME=$(/usr/bin/cat /proc/sys/kernel/hostname)
[[ -z "${MYHNAME}" ]] && MYHNAME=$(/usr/bin/hostnamectl | /usr/bin/awk '/hostname/ {print $NF;}')
[[ -z "${MYHNAME}" ]] && { echo "Cannot determine hostname. Aborting."; exit 1; }

## make sure the locally configured hostname is the same with the external one
[[ "${MYHNAME}" != "${REVERSE}" ]] && { echo "detected hostname ${MYHNAME} does not corespond to reverse dns name ${REVERSE}"; exit 1; }
[[ -n "${XRDSH_DEBUG}" ]] && echo "The FQDN appears to be : ${MYHNAME}"

## XROOTD Manager info
MANAGER_HOST_PORT=$( /bin/awk -F": " '/seioDaemons/ { gsub ("root://","",$2); print $2 }' <<< "${SE_INFO}" ) #'
IFS=':' read -r -a mgr_host_port_arr <<< "${MANAGER_HOST_PORT}"
MANAGERHOST="${mgr_host_port_arr[0]}"
#MANAGERPORT="${mgr_host_port_arr[1]}"

LOCALPATHPFX=$(/bin/awk -F": " '/seStoragePath/ {print $2;}'  <<< "${SE_INFO}" ) #'

###############################################################################################
## WHAT IS MY ROLE?
# Default assumption
is_manager="0"
ROLE="server"

# ipv4 ips recorded to the manager fqdn
local DNS_QUERY_IPv4 MANAGER_IP_LIST
DNS_QUERY_IPv4=$(host -t A "${MANAGERHOST}")
[[ "${DNS_QUERY_IPv4}" =~ no.+record ]] || [[ "${DNS_QUERY_IPv4}" =~ NXDOMAIN ]] && DNS_QUERY_IPv4=""
MANAGER_IP_LIST=$(/bin/awk '{print $NF;}' <<< "${DNS_QUERY_IPv4}") #'

# ipv6 logic; we don't use it as storage have to be dual stack
# ipv6 ips recorded to the manager fqdn
# local DNS_QUERY_IPv6 MANAGER_IPv6_LIST
# DNS_QUERY_IPv6=$(host -t AAAA ${MANAGERHOST})
# [[ "${DNS_QUERY_IPv6}" =~ no.+record ]] || [[ "${DNS_QUERY_IPv6}" =~ NXDOMAIN ]] && DNS_QUERY_IPv6=""
# MANAGER_IPv6_LIST=$(/bin/awk '{print $NF;}'  <<< "${DNS_QUERY_IPv6}") #'

#is my ip in manager ip list; so far we check only for ipv4 as storage have to be dual-stack anyway
[[ "${MANAGER_IP_LIST}" =~ ${MYIP} ]] && { is_manager="1"; ROLE="manager"; }

## if MANGERHOST fqdn is an alias then register servers to all ips
MANAGER_ALIAS=$(echo "${MANAGER_IP_LIST}" | /usr/bin/wc -l)

## instance name can be something else; to be used when starting multiple servers, but we are not doing this
[[ "${is_manager}" -eq "1" ]] && INSTANCE_NAME="manager" || INSTANCE_NAME="server"

export MONALISA_FQDN MANAGERHOST LOCALPATHPFX ROLE INSTANCE_NAME MANAGER_ALIAS

}

######################################
set_system () {
# if we are called by mistake (when XRD_DONOTRECONF is enabled) then just return
[[ -n "${XRD_DONOTRECONF}" ]] && return 0;

# Get all upstream server info (after first source of system.cnf);
# it will get also the locations of configurations and scripts

# we must pass the set_system args to serverinfo
# this is needed for customization of template and final xrootd configuration file
serverinfo "$@"

#######################
## Customize XRDCF file
#######################
if [[ -n "${XRDSH_DEBUG}" ]]; then
  echo "XRDSH dir is : ${XRDSHDIR}"
  echo "XRDCONFDIR is : ${XRDCONFDIR}"
  echo "XRDCF_TMP file is : ${XRDCF_TMP}"
  echo "XRDCF file is : ${XRDCF}"
fi

cp -f "${XRDCF_TMP}" "${XRDCF}"

## if set in system.cnf set the debug value in configuration file
if [[ -n "${XRDDEBUG}" ]]; then
    cfg_set_xrdvalue "${XRDCF}"  __XRD_DEBUG yes
    cfg_set_xrdvalue "${XRDCF}" __CMSD_DEBUG yes
fi

## set the instance name for both processes xrootd and cmsd
cfg_set_xrdvalue "${XRDCF}"  __XRD_INSTANCE_NAME "${INSTANCE_NAME}"
cfg_set_xrdvalue "${XRDCF}" __CMSD_INSTANCE_NAME "${INSTANCE_NAME}"

## set the xrootd and cmsd log file
## set "=" in front for disabling automatic fencing -- DO NOT USE YET BECAUSE OF servMon.sh
local XRD_LOG CMSD_LOG XRD_PIDFILE CMSD_PIDFILE

XRD_LOG="${XRDRUNDIR}/logs/xrdlog"
CMSD_LOG="${XRDRUNDIR}/logs/cmslog"
cfg_set_xrdvalue "${XRDCF}"  __XRD_LOG "${XRD_LOG}"
cfg_set_xrdvalue "${XRDCF}" __CMSD_LOG "${CMSD_LOG}"

## set the xrootd and cmsd PID file
XRD_PIDFILE="${XRDRUNDIR}/admin/xrd_${INSTANCE_NAME}.pid"
CMSD_PIDFILE="${XRDRUNDIR}/admin/cmsd_${INSTANCE_NAME}.pid"
cfg_set_xrdvalue "${XRDCF}"  __XRD_PIDFILE "${XRD_PIDFILE}"
cfg_set_xrdvalue "${XRDCF}" __CMSD_PIDFILE "${CMSD_PIDFILE}"

# ApMon files
export apmonPidFile="${XRDRUNDIR}/admin/apmon.pid"
export apmonLogFile="${XRDRUNDIR}/logs/apmon.log"

## Subscribe to all redirector ips and use load-balancing mode
## see http://xrootd.org/doc/dev49/cms_config.htm#_Toc506069400
(( IS_MANAGER_ALIAS > 1 )) && sed --follow-symlinks -i '/all\.manager/s/.*/all.manager all $myRedirector+ $portCMSD/' "${XRDCF}"

# Set readonly if set up in the environment
[[ -n "${XRDREADONLY}" ]] && sed --follow-symlinks -i '/all.export/s/writable/notwritable/' "${XRDCF}";

sed --follow-symlinks -i "
s#SITENAME#${SE_NAME}#g;
s#MANAGERHOST#${MANAGERHOST}#g;
s#LOCALPATHPFX#${LOCALPATHPFX}#g;
s#LOCALROOT#${LOCALROOT}#g;
s#XRDSERVERPORT#${XRDSERVERPORT}#g;
s#XRDMANAGERPORT#${XRDMANAGERPORT}#g;
s#CMSDSERVERPORT#${CMSDSERVERPORT}#g;
s#CMSDMANAGERPORT#${CMSDMANAGERPORT}#g;
s#ACCLIB#${ACCLIB}#g;
s#MONALISA_HOST#${MONALISA_FQDN}#g;
s#XRDRUNDIR#${XRDRUNDIR}#g;
" "${XRDCF}";

# write storage partitions; convert the /n to actual CRs and then pass that variable to perl; (otherwise it needs to be exported)
SPACE=$(echo -e "${OSSCACHE}") perl -pi -e 's/OSSCACHE/$ENV{SPACE}/g;' "${XRDCF}";

}

######################################
## create TkAuthz.Authorization file; take as argument the place where are the public keys
create_tkauthz() {
  local PRIV_KEY_DIR; PRIV_KEY_DIR=$1
  local TK_FILE="${PRIV_KEY_DIR}/TkAuthz.Authorization"

  (
  #########################################
  # the root of the exported namespace you allow to export on your disk servers
  # just add all directories you want to allow this is only taken into account if you use the TokenAuthzOfs OFS
  # Of course, the localroot prefix here should be omitted
  # If the cluster is (correctly!) configured with the right
  # localroot option, allowing / is just fine and 100% secure. That should be considered normal.
  echo 'EXPORT PATH:/ VO:*     ACCESS:ALLOW CERT:*'

  # rules, which define which paths need authorization; leave it like that, that is safe
  echo 'RULE PATH:/ AUTHZ:delete|read|write|write-once| NOAUTHZ:| VO:*| CERT:IGNORE'

  echo "KEY VO:* PRIVKEY:${PRIV_KEY_DIR}/privkey.pem PUBKEY:${PRIV_KEY_DIR}/pubkey.pem"

  ) > "${TK_FILE}"

  /bin/chmod 600 "${TK_FILE}"
}

######################################
checkkeys() {
  getLocations

  local KEYS_REPO="http://alitorrent.cern.ch/src/xrd3/keys/"
  local authz_dir1="/etc/grid-security/xrootd/"
  local authz_dir2="${XRDHOME}/.globus/xrootd/"
  local authz_dir3="${XRDHOME}/.authz/xrootd/"

  local authz_dir=${authz_dir3} # default dir

  for dir in ${authz_dir1} ${authz_dir2} ${authz_dir3}; do  ## unless keys are found in locations searched by xrootd
    [[ -e ${dir}/privkey.pem && -e ${dir}/pubkey.pem ]] && return 0;
  done

  [[ $(/usr/bin/id -u) == "0" ]] && authz_dir=${authz_dir1}
  /bin/mkdir -p "${authz_dir}"
  echo "Getting Keys and bootstrapping ${authz_dir}/TkAuthz.Authorization ..."

  /usr/bin/curl -fsSLk -o "${authz_dir}/pubkey.pem" "${KEYS_REPO}/pubkey.pem" -o "${authz_dir}/privkey.pem" "${KEYS_REPO}/privkey.pem"
  /bin/chmod 400 "${authz_dir}/privkey.pem" "${authz_dir}/pubkey.pem"

  create_tkauthz "${authz_dir}"
  /bin/chown -R "${XRDUSER}" "${XRDHOME}/.authz"

}

######################################
removecron() {
  local cron_file="/tmp/cron.$RANDOM.xrd.sh";
  /usr/bin/crontab -l | sed '/\s*#.*/! { /xrd\.sh/ d}' > ${cron_file}; # get current crontab and delete uncommented xrd.sh lines
  /usr/bin/crontab ${cron_file}; # put back the cron without xrd.sh
  /bin/rm -f ${cron_file};
}

######################################
addcron() {
  getLocations
  removecron # clean up the old xrd.sh cron line
  cron_file="/tmp/cron.${RANDOM}.xrd.sh";
  /usr/bin/crontab -l > "${cron_file}"; # get current crontab

  ## add to cron_file the xrd.sh command
  echo -ne "\
*/5 * * * * BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -c    >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\\n
0   3 * * * BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -logs >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\\n
@reboot     BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -c    >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\\n" >> ${cron_file}

  /usr/bin/crontab "${cron_file}"; # put back the cron with xrd.sh
  /bin/rm -f "${cron_file}";
}


######################################
getSrvToMon() {
  local se pid
  srvToMon=""
  [[ -n "${SE_NAME}" ]] && se="${SE_NAME}_" || return 1;

  for typ in manager server ; do
    for srv in xrootd cmsd ; do
      pid=$(/usr/bin/pgrep -f -U "$USER" "$srv .*$typ" | head -1)
      [[ -n "${pid}" ]] && srvToMon="${srvToMon} ${se}${typ}_${srv} ${pid}"
    done
  done
}

######################################
servMon() {
  local se
  [[ -n "${SE_NAME}" ]] && se="${SE_NAME}_" || return 1;

  /usr/sbin/servMon.sh -p "${apmonPidFile}" "${se}xrootd" "$@"
  echo
}

######################################
startMon() {
    [[ -z "${MONALISA_FQDN}" ]] && return 1;

    getSrvToMon
    echo -n "Starting ApMon [${srvToMon}] ..."
    servMon -f "${srvToMon}"
    echo_passed
    echo
}

######################################
create_limits_conf () {

local FILE="99-xrootd_limits.conf"

echo "The generated file ${FILE} should be placed in /etc/security/limits.d/"

cat > ${FILE} <<EOF
${USER}         hard    nofile          65536
${USER}         soft    nofile          65536

${USER}         hard    nproc          1024
${USER}         soft    nproc          1024

EOF

echo "Generated file is ${FILE} with content :"
cat ${FILE}

echo "try : sudo cp ${FILE} /etc/security/limits.d/"
}

######################################
handlelogs() {
  getLocations
  cd "${XRDRUNDIR}" || { echo "XRDRUNDIR not found"; return 1; }
  /bin/mkdir -p "${XRDRUNDIR}/logsbackup"
  local LOCK
  LOCK="${XRDRUNDIR}/logs/HANDLELOGS.lock"
  #local todaynow=$(date +%Y%m%d_%k%M%S)

  cd "${XRDRUNDIR}/logs" || { echo "XRDRUNDIR/logs not found"; return 1; }
  not_compressed=$(/bin/find . -type f -not -name '*.bz2' -not -name 'stage_log' -not -name 'cmslog' -not -name 'xrdlog' -not -name 'pstg_log' -not -name 'xrd.watchdog.log' -not -name 'apmon.log' -not -name 'servMon.log' -print)

  if [[ ! -f "${LOCK}" ]]; then
    touch "${LOCK}"
    for log in ${not_compressed}; do /usr/bin/bzip2 -9fq "${log}"; done
    /bin/rm -f "${LOCK}"
  fi

  # move compressed to logs backup
  find "${XRDRUNDIR}/logs/" -type f -name "*log.*.bz2" -exec mv '{}' "${XRDRUNDIR}/logsbackup/" \; &> /dev/null
}

######################################
execEnvironment() {
    /bin/mkdir -p "${XRDRUNDIR}/logs/" "${XRDRUNDIR}/admin/" "${XRDRUNDIR}/core/${USER}_${1}"
    /bin/chmod -R 755 "${XRDRUNDIR}/logs" "${XRDRUNDIR}/admin" "${XRDRUNDIR}/core"

    /bin/chown -R "${XRDUSER}" "${XRDRUNDIR}/core" "${XRDRUNDIR}/logs" "${XRDRUNDIR}/admin"

    ULIM_OPENF=$(ulimit -n)
    ULIM_USR_PROC=$(ulimit -u)

    ulimit -n "${XRDMAXFD}"

    if (( ULIM_OPENF < XRDMAXFD )) ; then
      echo "Fatal: This machine does not allow more than ${XRDMAXFD} file descriptors. At least 65000 are needed for serious operation"
      echo "use xrd.sh -limits for generating the limits file"
      exit -1
    fi

    if (( ULIM_USR_PROC < 512 )); then
        echo "This machine does not allow more than ${ULIM_USR_PROC} user processes."
        echo "create a .conf file in /etc/security/limits.d/ with needed settings"
        echo "use xrd.sh -limits for generating the limits file"
    fi

}

######################################
generate_systemd () {
  if [[ -n "${XRD_DONOTRECONF}" ]]; then
    getLocations "$@"
  else
    set_system "$@"
  fi

# get information from the configuration file ${XRDCF}
eval "$(sed -ne 's/\#@@/local /gp;' ${XRDCF})"
[[ -z "${INSTANCE_NAME}"  ]] && local INSTANCE_NAME="${__XRD_INSTANCE_NAME}"

# first we prepare the configuration file (it should be prezent)
cp -f ${XRDCF} xrootd-${INSTANCE_NAME}.cfg

# remove all.pidpath; there will be files in /tmp/<instance name>/ but we will ignore them
sed -i '/all.pidpath/d' xrootd-${INSTANCE_NAME}.cfg

# adjust all.adminpath to /var/adm/xrootd-<instance name>
sed -i "/adminpath/s/.*/\/var\/adm\/xrootd-${INSTANCE_NAME}/" xrootd-${INSTANCE_NAME}.cfg

echo -e "The configuration file should be copied to /etc/xrootd/ directory :
sudo cp -f xrootd-${INSTANCE_NAME}.cfg /etc/xrootd/

and then enable the system provided xrootd systemd service :
sudo systemctl enable cmsd@${INSTANCE_NAME}.service xrootd@${INSTANCE_NAME}.service

N.B.!!! the format used specify the _instance_name_ : xrootd@<INSTANCE_NAME>.service
and assumes the configuration name format (and path) : /etc/xrootd/xrootd-<INSTANCE_NAME>.cfg
"
# now we have to customize the system provided systemd files
local cmsd_systemd_dir="/etc/systemd/system/cmsd@${INSTANCE_NAME}.service.d/"
local cmsd_custom_file="override_cmsd.conf"

local xrootd_systemd_dir="/etc/systemd/system/xrootd@${INSTANCE_NAME}.service.d/"
local xrootd_custom_file="override_xrootd.conf"

# log file is automatically "fenced" (taged with instance name) so lets leave it like this

# cmsd systemd conf file
cat > "${cmsd_custom_file}" <<EOF
[Unit]
AssertPathExists=/etc/xrootd/xrootd-%i.cfg
PartOf=xrootd@%i.service
Before=xrootd@%i.service

[Service]
User=${XRDUSER}
Group=${XRDUSER}
ExecStartPre=/usr/bin/mkdir -p /var/adm/xrootd-%i
ExecStartPre=/usr/bin/chown -R ${XRDUSER}:${XRDUSER} /var/adm/xrootd-%i
ExecStartPre=/usr/bin/chmod 1777 /var/log/xrootd /var/run/xrootd
WorkingDirectory=/var/adm/xrootd-%i

ExecStart=
ExecStart=/usr/bin/cmsd ${__CMSD_DEBUG} -k fifo -l /var/log/xrootd/cmsd.log -s /var/run/xrootd/cmsd-%i.pid -c /etc/xrootd/xrootd-%i.cfg -n %i

EOF

# xrootd systemd conf file
cat > "${xrootd_custom_file}" <<EOF
[Unit]
AssertPathExists=/etc/xrootd/xrootd-%i.cfg
After=cmsd@%i.service
BindsTo=cmsd@%i.service

[Service]
User=${XRDUSER}
Group=${XRDUSER}
ExecStartPre=/usr/bin/mkdir -p /var/adm/xrootd-%i
ExecStartPre=/usr/bin/chown -R ${XRDUSER}:${XRDUSER} /var/adm/xrootd-%i
ExecStartPre=/usr/bin/chmod 1777 /var/log/xrootd /var/run/xrootd
WorkingDirectory=/var/adm/xrootd-%i

ExecStart=
ExecStart=/usr/bin/xrootd ${__XRD_DEBUG} -k fifo -l /var/log/xrootd/xrootd.log -s /var/run/xrootd/xrootd-%i.pid -c /etc/xrootd/xrootd-%i.cfg -n %i

EOF

echo "
Check the contents of the two systemd service override files (${cmsd_custom_file} and ${xrootd_custom_file})
and then copy these files to the locations for systemd service customisation :
sudo -- bash -c 'mkdir -p ${cmsd_systemd_dir} ; cp -f ${cmsd_custom_file} ${cmsd_systemd_dir}'
sudo -- bash -c 'mkdir -p ${xrootd_systemd_dir} ; cp -f ${xrootd_custom_file} ${xrootd_systemd_dir}'

then start the services:
systemctl start xrootd@${INSTANCE_NAME}.service
systemctl status xrootd@${INSTANCE_NAME}.service
"
}

######################################
killXRD() {
    echo -n "Stopping xrootd/cmsd: "
    local XRDSHUSER xrd_procs
    XRDSHUSER=$(id -nu)

    xrd_procs=$(/usr/bin/pgrep -u "${XRDSHUSER}" "cmsd|xrootd")
    [[ -n "${xrd_procs}" ]] && /usr/bin/pkill -u "${XRDSHUSER}" "xrootd|cmsd"

    xrd_procs=$(/usr/bin/pgrep -u "${XRDSHUSER}" "cmsd|xrootd")
    [[ -n "${xrd_procs}" ]] && { /bin/sleep 2; /usr/bin/pkill -9 -u "${XRDSHUSER}" "xrootd|cmsd"; }

    xrd_procs=$(/usr/bin/pgrep -u "${XRDSHUSER}" "cmsd|xrootd")
    [[ -z "${xrd_procs}" ]] && echo_success || echo_failure
    echo

    [[ -z "${XRDSH_NOAPMON}" ]] && { echo -n "Stopping ApMon:"; servMon -k; /usr/bin/pkill -f -u "${XRDSHUSER}" mpxstats; echo; }
}

######################################
startXRD () {
    if [[ -n "${XRD_DONOTRECONF}" ]]; then
      getLocations "$@"
      eval "$(sed -ne 's/\#@@/local /gp;' ${XRDCF})"
      INSTANCE_NAME="${__XRD_INSTANCE_NAME}"
    else
      set_system "$@"
    fi

    execEnvironment "${INSTANCE_NAME}" || exit

    ## STARTING SERVICES WITH THE CUSTOMIZED CONFIGURATION
    echo "Starting cmsd+xrootd [${INSTANCE_NAME}]: "
    startXROOTDprocs "${XRDCF}"
    sleep 1

    local CMSD_PID_FILE=$(getPidFiles_cmsd)
    local CMSD_PID=$( < "${CMSD_PID_FILE}" ) #"
    [[ -n "${CMSD_PID}" ]] && { echo -ne "CMSD pid :\t${CMSD_PID} -> "; echo_success; echo; } || { echo "CMSD pid not found"; echo_failure; echo; }

    local XRD_PID_FILE=$(getPidFiles_xrd)
    local XRD_PID=$( < "${XRD_PID_FILE}" ) #"
    [[ -n "${XRD_PID}" ]] && { echo -ne "XROOTD pid :\t${XRD_PID} -> "; echo_success; echo; } || { echo "XROOTD pid not found"; echo_failure; echo; }

    [[ -z "${XRDSH_NOAPMON}" ]] && { sleep 1; startMon; sleep 1; }
}

######################################
restartXRD () {
    killXRD
    startXRD "$@"
}

######################################
checkstate () {
echo "******************************************"
date
echo "******************************************"

local xrd_pid cmsd_pid returnval is_apmon_pid returnval
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

# is apmon is enabled
if [[ -z "${XRDSH_NOAPMON}" ]]; then
    # find pid file of apmon
    is_apmon_pid=$(/bin/find "${apmonPidFile}*" 2>/dev/null | /usr/bin/wc -l)

    if (( is_apmon_pid > 0 )) ; then
      echo -n "apmon:"; echo_success; echo;
    else
      echo -n "apmon:"; echo_failure; echo; returnval=1;
    fi
fi

return "${returnval}"
}

######################
##    Main logic    ##
######################
xrdsh_main() {
if [[ "$1" == "-c" ]]; then  ## check and restart if not running
    shift

    # if we are reconfiguring then also check the keys
    [[ -z "${XRD_DONOTRECONF}" ]] && checkkeys

    addcron # it will remove old xrd.sh line and

    # check status of xrootd and cmsd pids - if checkstate return error then restart all
    checkstate
    local state=$?
    [[ ${state} != "0" ]] && restartXRD "$@"

elif [[ "$1" == "-status" ]]; then
    checkstate
elif [[ "$1" == "-f" ]]; then   ## force restart
    shift
    addcron # it will remove old xrd.sh line and
    [[ -z "${XRD_DONOTRECONF}" ]] && checkkeys
    /bin/date
    echo "(Re-)Starting ...."
    restartXRD "$@"
    checkstate
elif [[ "$1" == "-k" ]]; then  ## kill running processes
    removecron
    killXRD
    checkstate
elif [[ "$1" == "-logs" ]]; then  ## handlelogs
    handlelogs
elif [[ "$1" == "-conf" ]]; then  ## create configuration
    shift
    set_system "$@"
elif [[ "$1" == "-systemd" ]]; then  ## create configuration
    shift
    generate_systemd "$@"
elif [[ "$1" == "-getkeys" ]]; then  ## download keys and create TkAuthz.Authorization file
    checkkeys
elif [[ "$1" == "-addcron" ]]; then  ## add cron line
    addcron # it will remove old xrd.sh line and
elif [[ "$1" == "-limits" ]]; then  ## generate limits file
    create_limits_conf
else
    echo "usage: xrd.sh arg";
    echo "where argument is _one_ of :"
    echo " [-f] force restart";
    echo " [-c] check and restart if not running";
    echo " [-k] kill running processes";
    echo " [-status] show if xrootd|cmsd pids are present";
    echo " [-logs] manage the logs";
    echo " [-conf] just (re)create configuration; optional args : <configuration_template> <xrootd_configuration>";
    echo " [-getkeys] just get keys";
    echo " [-addcron] add/refresh cron line";
    echo " [-limits] generate limits file";
    echo " [-systemd] generate systemd services files";
    echo "";
    echo "Environment variables:";
    echo "  XRDSH_NOWARN_ASLIB : if set (any value) do not warn xrd.sh is sourced"
    echo "  XRDREADONLY : if set (any value) export path as not writable - server will not be elected for writes "
    echo "  XRD_DONOTRECONF : if set (any value) the configuration of template file will be skipped;
  the conf file that will be used is either the default XRDCONFDIR/xrootd.xrootd.cf, the argument specified to -c,-f,-conf
         "
    echo ">>>>>> XRDSH_NOAPMON : if set (any value) ApMon components WILL NOT BE USED"
    echo "  XRDRUNDIR : location of admin,core,logs,logsbackup dirs; if not set it will be XRDSHDIR/run/"
    echo "  XRDCONFDIR : location of system.cnf and XRDCF (default xrootd.xrootd.cf) conf files; if not set it will be XRDSHDIR/xrootd.conf/"
    echo "  XRDCONF : main configuration file - usually (default) named system.cnf; if not set it will have the value of XRDCONFDIR/system.cnf"
    echo "  XRDSH_DEBUG : if set (any value) it will enable various printouts of srd.sh"
fi
}

###########################
###   BEGIN EXECUTION   ###
###########################

## Allow loading functions as library
#  Warns unless SKIPWARN_XRDSH_ASLIB is set
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] ; then
    [[ -z "${XRDSH_NOWARN_ASLIB}" ]] && echo "Warning: using xrd.sh as library!"
    return 0
fi

check_prerequisites
xrdsh_main "$@"
