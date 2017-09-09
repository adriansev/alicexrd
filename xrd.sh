#!/bin/bash

######################################
serverinfo() {
  ## Network information and validity checking
  MYNET=$(/usr/bin/curl -fsSLk http://alimonitor.cern.ch/services/ip.jsp)
  MYIP=$(echo "${MYNET}" | /bin/awk '/IP/ {gsub("IP:","",$1); print $1}')
  REVERSE=$(echo "${MYNET}" | /bin/awk '/FQDN/ {gsub("FQDN:","",$1); print $1}')

  ## make sure the exit public ip is locally configured
  ip_list=$(/sbin/ip addr show scope global permanent up | /bin/awk '/inet/ {split ($2,ip,"/"); print ip[1]}')
  found_at=$(expr index "${ip_list}" "$MYIP")
  [[ "${found_at}" == "0" ]] && { echo "Server without public/rutable ip. No NAT schema supported at this moment" && exit 10; }

  ## what is my local set hostname
  [[ -z "$myhost" ]] && myhost=$(/bin/hostname -f)
  [[ -z "$myhost" ]] && myhost=$(/bin/hostname)
  [[ -z "$myhost" ]] && echo "Cannot determine hostname. Aborting." && exit 1

  ## make sure the locally configured hostname is the same with the external one
  [[ "$myhost" != "$REVERSE" ]] && { echo "detected hostname $myhost does not corespond to reverse dns name $REVERSE" && exit 10; }
  echo "The fully qualified hostname appears to be $myhost"

  ## Find information about site from ML
  MONALISA_IP=$(/usr/bin/curl -s http://alimonitor.cern.ch/services/getClosestSite.jsp?ml_ip=true | /bin/awk -F, '{print $1}')
  MONALISA_HOST=$(/usr/bin/host ${MONALISA_IP} | /bin/awk '{ print substr ($NF,1,length($NF)-1);}')

  se_info=$(/usr/bin/curl -fsSLk http://alimonitor.cern.ch/services/se.jsp?se=${SE_NAME})
  [[ "${se_info}" == "null" ]] && { echo "The stated SE name ${SE_NAME} is not found to be valid by MonaLisa" && exit 10; }

  MANAGERHOST=$(echo "${se_info}" | /bin/awk -F": " '/seioDaemons/ { gsub ("root://","",$2);gsub (":1094","",$2) ; print $2 }' )
  LOCALPATHPFX=$(echo "${se_info}" | /bin/awk -F": " '/seStoragePath/ { print $2 }' )

  IS_MANAGER_ALIAS=$(/usr/bin/host -t A ${MANAGERHOST}| wc -l)
  ## see http://xrootd.org/doc/dev45/cms_config.htm#_Toc454223020
  (( IS_MANAGER_ALIAS > 1 )) && MANAGERHOST="all ${MANAGERHOST}+"

  ##  What i am?
  # default role - server
  server="yes"; manager=""; nproc=1;

  # unless i am manager
  if [[ "x$myhost" == "x$MANAGERHOST" ]]; then
    manager="yes";
    server="";
  fi

  if [[ "$manager" == "yes" ]]; then
    INSTANCE_NAME="manager"
  else
    INSTANCE_NAME="server"
  fi

  export INSTANCE_NAME
  export MONALISA_HOST
  export MANAGERHOST
  export LOCALPATHPFX
  export manager
  export server
  export nproc
}

######################################
set_formatters() {
BOOTUP=color
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"
}

######################################
check_prerequisites() {
[ ! -e "/usr/bin/dig" ] && { echo "dig command not found; do : yum -y install bind-utils.x86_64"; exit 1; }
[ ! -e "/usr/bin/wget" ] && { echo "wget command not found; do : yum -y install wget.x86_64"; exit 1; }
[ ! -e "/usr/bin/curl" ] && { echo "curl command not found; do : yum -y install curl.x86_64"; exit 1; }
[ ! -e "/usr/bin/bzip2" ] && { echo "bzip2 command not found (logs compression); do : yum -y install bzip2.x86_64"; exit 1; }
}

######################################
getLocations () {
# Define system settings
# Find configs, dirs, xrduser, ...

## find the location of xrd.sh script
SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SOURCE}" ]; do ## resolve $SOURCE until the file is no longer a symlink
  XRDSHDIR="$( cd -P "$(dirname "${SOURCE}" )" && pwd )"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${XRDSHDIR}/${SOURCE}" ## if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
XRDSHDIR="$(cd -P "$( dirname "${SOURCE}" )" && pwd)"

export XRDSHDIR

# make sure xrd.sh is executable by user and user group
/bin/chmod ug+x ${XRDSHDIR}/xrd.sh

# location of logs, admin, core dirs
XRDRUNDIR=${XRDRUNDIR:-$XRDSHDIR/run/}
export XRDRUNDIR

# location of configuration files; needs not be the same with xrd.sh location
XRDCONFDIR=${XRDCONFDIR:-$XRDSHDIR/xrootd.conf/}
export XRDCONFDIR

## LOCATIONS AND INFORMATIONS
export XRDCONF="${XRDCONFDIR}/system.cnf"
source ${XRDCONF}
}

######################################
set_system () {
getLocations

# Get all upstream server info (after first source of system.cnf)
serverinfo

## set the debug value in configuration file
if [[ -n "${XRDDEBUG}" ]]; then
    cfg_set_value ${XRDCONF}  __XRD_DEBUG yes
    cfg_set_value ${XRDCONF} __CMSD_DEBUG yes
fi

## set the instance name for both processes xrootd and cmsd
cfg_set_value ${XRDCONF}  __XRD_INSTANCE_NAME ${INSTANCE_NAME}
cfg_set_value ${XRDCONF} __CMSD_INSTANCE_NAME ${INSTANCE_NAME}

## set the xrootd and cmsd log file
## set "=" in front for disabling automatic fencing -- DO NOT USE YET BECAUSE OF servMon.sh
local  XRD_LOG="${XRDRUNDIR}/logs/xrdlog"
local CMSD_LOG="${XRDRUNDIR}/logs/cmslog"
cfg_set_value ${XRDCONF}  __XRD_LOG ${XRD_LOG}
cfg_set_value ${XRDCONF} __CMSD_LOG ${CMSD_LOG}

## set the xrootd and cmsd PID file
local  XRD_PIDFILE="${XRDRUNDIR}/admin/xrd_${INSTANCE_NAME}.pid"
local CMSD_PIDFILE="${XRDRUNDIR}/admin/cmsd_${INSTANCE_NAME}.pid"
cfg_set_value ${XRDCONF}  __XRD_PIDFILE ${XRD_PIDFILE}
cfg_set_value ${XRDCONF} __CMSD_PIDFILE ${CMSD_PIDFILE}

## second sourcing of system.cnf
source ${XRDCONF}

# ApMon files
export apmonPidFile=${XRDRUNDIR}/admin/apmon.pid
export apmonLogFile=${XRDRUNDIR}/logs/apmon.log

USER=${USER:-$LOGNAME}
[[ -z "$USER" ]] && USER=$(/usr/bin/id -nu)

SCRIPTUSER=$USER

## automatically asume that the owner of location of xrd.sh is XRDUSER
XRDUSER=$(/usr/bin/stat -c %U $XRDSHDIR)

## get the home dir of the designated xrd user
XRDHOME=$(getent passwd $XRDUSER | awk -F: '{print $(NF-1)}')
[[ -z "${XRDHOME}" ]] && { echo "Fatal: invalid home for user $XRDUSER"; exit 10;}

}

##########  FUNCTIONS   #############
echo_success() {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "[  "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_SUCCESS
  echo -n $"OK"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "  ]"
  echo -ne "\r"
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
  echo -ne "\r"
  return 0
}

######################################
echo_passed() {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "["
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo -n $"PASSED"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "]"
  echo -ne "\r"
  return 1
}

######################################
startUp() {
    if [[ "$SCRIPTUSER" == "root" ]]; then
      cd "$XRDSHDIR"
      /bin/su -s /bin/bash $XRDUSER -c "${EXECENV} $*";
      echo_passed
      # test $? -eq 0 && echo_success || echo_failure
      echo
    else
      ulimit -c unlimited
      $*
      echo_passed
      # test $? -eq 0 && echo_success || echo_failure
      echo
    fi
}

######################################
getPidFiles_xrd () {
ps -o args= $(pgrep -x xrootd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-s") {print $(x+1)} }}'
}

######################################
getPidFiles_cmsd () {
ps -o args= $(pgrep -x cmsd) | awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-s") {print $(x+1)} }}'
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
startXRDserv () {
local CFG="$1"

## get __XRD_ server arguments from config file.
eval $(sed -ne '/__XRD_/p' ${CFG})

## make sure that they are defined
[[ -z "${__XRD_INSTANCE_NAME}" || -z "${__XRD_LOG}" || -z "${__XRD_PIDFILE}" ]] && { startXRDserv_help; exit 1;}

## not matter how is enabled the debug mode means -d
[[ -n "${__XRD_DEBUG}" ]] && __XRD_DEBUG="-d"

local XRD_START="/usr/bin/xrootd -b ${__XRD_DEBUG} -n ${__XRD_INSTANCE_NAME} -l ${__XRD_LOG} -s ${__XRD_PIDFILE} -c ${CFG}"
eval ${XRD_START}
}

######################################
startCMSDserv () {
local CFG="$1"

## get __CMSD_ server arguments from config file.
eval $(sed -ne '/__CMSD_/p' ${CFG})

## make sure that they are defined
[[ -z "${__CMSD_INSTANCE_NAME}" || -z "${__CMSD_LOG}" || -z "${__CMSD_PIDFILE}" ]] && { startCMSDserv_help; exit 1;}

## not matter how is enabled the debug mode means -d
[[ -n "${__CMSD_DEBUG}" ]] && __CMSD_DEBUG="-d"

local CMSD_START="/usr/bin/cmsd -b ${__CMSD_DEBUG} -n ${__CMSD_INSTANCE_NAME} -l ${__CMSD_LOG} -s ${__CMSD_PIDFILE} -c ${CFG}"
eval ${CMSD_START}
}


######################################
createconf() {
  set_system

  echo "xrdsh dir is : ${XRDSHDIR}"
  echo "xrdconfdir is : ${XRDCONFDIR}"

  ###################
  export osscachetmp=$(echo -e $OSSCACHE);

  # Replace XRDSHDIR for service starting
  cd ${XRDSHDIR}
  cp -f alicexrdservices.tmp alicexrdservices;
  /usr/bin/perl -pi -e 's/XRDSHDIR/$ENV{XRDSHDIR}/g;' ${XRDSHDIR}/alicexrdservices;

  cd ${XRDCONFDIR}
  for name in $(/bin/find ${XRDCONFDIR} -type f -name "*.tmp"); do
    newname=$(echo ${name} | /bin/sed s/\.tmp// )

    cp -f ${name} ${newname};

    [[ -n "${XRDREADONLY}" ]] && /usr/bin/perl -pi -e 's/\bwritable\b/notwritable/g if /all.export/;' ${newname};

    # Set xrootd site name
    /usr/bin/perl -pi -e 's/SITENAME/$ENV{SE_NAME}/g;' ${newname};

    # Replace XRDSHDIR and XRDRUNDIR
    /usr/bin/perl -pi -e 's/XRDSHDIR/$ENV{XRDSHDIR}/g; s/XRDRUNDIR/$ENV{XRDRUNDIR}/g;' ${newname};

    # Substitute all the variables into the templates
    /usr/bin/perl -pi -e 's/LOCALPATHPFX/$ENV{LOCALPATHPFX}/g; s/LOCALROOT/$ENV{LOCALROOT}/g; s/XRDUSER/$ENV{XRDUSER}/g; s/MANAGERHOST/$ENV{MANAGERHOST}/g; s/XRDSERVERPORT/$ENV{XRDSERVERPORT}/g; s/XRDMANAGERPORT/$ENV{XRDMANAGERPORT}/g; s/CMSDSERVERPORT/$ENV{CMSDSERVERPORT}/g; s/CMSDMANAGERPORT/$ENV{CMSDMANAGERPORT}/g;' ${newname};

    # write storage partitions
    /usr/bin/perl -pi -e 's/OSSCACHE/$ENV{osscachetmp}/g;' ${newname};

    # if [ -n "$OSSCACHE" ] ; then
    #     echo -e "\n\n\n${OSSCACHE}\n\n\n" >> $newname
    # fi

    # Monalisa stuff which has to be commented out in some cases
    if [[ -n "$MONALISA_HOST" ]] ; then
      /usr/bin/perl -pi -e 's/MONALISA_HOST/$ENV{MONALISA_HOST}/g' ${newname};
    else
      /usr/bin/perl -pi -e 's/(.*MONALISA_HOST.*)/#\1/g' ${newname};
    fi

    # XrdAcc stuff which has to be commented out in some cases
    if [[ -n "$ACCLIB" ]] ; then
      /usr/bin/perl -pi -e 's/ACCLIB/$ENV{ACCLIB}/g' ${newname}
    else
      /usr/bin/perl -pi -e 's/(.*ACCLIB.*)/#\1/g; s/(.*ofs\.authorize.*)/#\1/g' ${newname}
    fi

    # Xrdn2n stuff which has to be commented out in some cases
    if [[ -z "$LOCALPATHPFX" ]] ; then
      /usr/bin/perl -pi -e 's/(.*oss\.namelib.*)/#\1/g' ${newname}
    fi


  done;

  /bin/unlink ${XRDCONFDIR}/xrootd.cf >&/dev/null; /bin/ln -s ${XRDCONFDIR}/xrootd.xrootd.cf  ${XRDCONFDIR}/xrootd.cf;

  cd -;
}

######################################
bootstrap() {
  createconf
  /bin/mkdir -p ${LOCALROOT}/${LOCALPATHPFX}
  [[ "${server}" == "yes" ]] && chown $XRDUSER ${LOCALROOT}/${LOCALPATHPFX}
}

######################################
## create TkAuthz.Authorization file; take as argument the place where are the public keys
create_tkauthz() {
  local PRIV_KEY_DIR; PRIV_KEY_DIR=$1

  echo "KEY VO:*       PRIVKEY:${PRIV_KEY_DIR}/privkey.pem PUBKEY:${PRIV_KEY_DIR}/pubkey.pem" > ${PRIV_KEY_DIR}/TkAuthz.Authorization
  /bin/chmod 600 ${PRIV_KEY_DIR}/TkAuthz.Authorization

  #########################################
  # the root of the exported namespace you allow to export on your disk servers
  # just add all directories you want to allow
  # this is only taken into account if you use the TokenAuthzOfs OFS
  # Of course, the localroot prefix here should be omitted
  # If the cluster is (correctly!) configured with the right
  # localroot option, allowing / is just fine and 100% secure. That should be
  # considered normal.
  echo 'EXPORT PATH:/ VO:*     ACCESS:ALLOW CERT:*' >> ${PRIV_KEY_DIR}/TkAuthz.Authorization

  # rules, which define which paths need authorization; leave it like that, that is safe
  echo 'RULE PATH:/ AUTHZ:delete|write|write-once| NOAUTHZ:read| VO:*| CERT:*' >> ${PRIV_KEY_DIR}/TkAuthz.Authorization
}

######################################
checkkeys() {
    KEYS_REPO="http://alitorrent.cern.ch/src/xrd3/keys/"

    authz_dir1="/etc/grid-security/xrootd/"
    authz_dir2="${XRDHOME}/.globus/xrootd/"
    authz_dir3="${XRDHOME}/.authz/xrootd/"

    authz_dir=${authz_dir3} # default dir

    if [[ -n "$ACCLIB" ]]; then
      installkeys=yes ## default action is installing keys in default dir

      for dir in ${authz_dir1} ${authz_dir2} ${authz_dir3}; do  ## unless keys are found in locations searched by xrootd
        [[ -e ${dir}/privkey.pem && -e ${dir}/pubkey.pem ]] && installkeys=no && break
      done

      if [[ "$installkeys" == "yes" ]]; then
        [[ $(/usr/bin/id -u) == "0" ]] && authz_dir=${authz_dir1}
        /bin/mkdir -p ${authz_dir}
        echo "Getting Keys and bootstrapping ${authz_dir}/TkAuthz.Authorization ..."

        cd ${authz_dir}
        /usr/bin/curl -fsSL -O ${KEYS_REPO}/pubkey.pem -O ${KEYS_REPO}/privkey.pem
        /bin/chmod 400 ${authz_dir}/privkey.pem ${authz_dir}/pubkey.pem

        create_tkauthz ${authz_dir}
        /bin/chown -R $XRDUSER $XRDHOME/.authz
      fi

    cd ~
    fi
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
  cron_file="/tmp/cron.$RANDOM.xrd.sh";
  /usr/bin/crontab -l > ${cron_file}; # get current crontab

  ## add to cron_file the xrd.sh command
  echo -ne "\
*/5 * * * * BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -c    >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\n\
0   3 * * * BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -logs >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\n\
@reboot     BASH_ENV=$HOME/.bash_profile ${XRDSHDIR}/xrd.sh -c    >> ${XRDRUNDIR}/logs/xrd.watchdog.log 2>&1\n" >> ${cron_file}

  /usr/bin/crontab ${cron_file}; # put back the cron with xrd.sh
  /bin/rm -f ${cron_file};
}


######################################
getSrvToMon() {
  srvToMon=""
  [[ -n "${SE_NAME}" ]] && se="${SE_NAME}_"

  for typ in manager server ; do
    for srv in xrootd cmsd ; do
      pid=$(/usr/bin/pgrep -f -U $USER "$srv .*$typ" | head -1)
      [[ -n "${pid}" ]] && srvToMon="$srvToMon ${se}${typ}_${srv} $pid"
    done
  done
}

######################################
servMon() {
  [[ -n "${SE_NAME}" ]] && se="${SE_NAME}_"

  startUp /usr/sbin/servMon.sh -p ${apmonPidFile} ${se}xrootd $*
  echo
}

######################################
startMon() {
    [[ -z "${MONALISA_HOST}" ]] && return

    getSrvToMon
    echo -n "Starting ApMon [$srvToMon] ..."
    servMon -f $srvToMon
    echo_passed
    echo
}

######################################
create_limits_conf () {
set_system

local FILE="99-xrootd_limits.conf"

echo "The generated file ${FILE} should be placed in /etc/security/limits.d/"

cat > ${FILE} <<EOF
${XRDUSER}         hard    nofile          65536
${XRDUSER}         soft    nofile          65536

${XRDUSER}         hard    nproc          1024
${XRDUSER}         soft    nproc          1024

EOF

echo "Generated file is ${FILE} with content :"
cat ${FILE}

echo "try : sudo cp ${FILE} /etc/security/limits.d/"
}

######################################
handlelogs() {
  cd ${XRDRUNDIR}
  /bin/mkdir -p ${XRDRUNDIR}/logsbackup
  local LOCK=${XRDRUNDIR}/logs/HANDLELOGS.lock
  #local todaynow=$(date +%Y%m%d_%k%M%S)

  cd ${XRDRUNDIR}/logs
  not_compressed=$(/bin/find . -type f -not -name '*.bz2' -not -name 'stage_log' -not -name 'cmslog' -not -name 'xrdlog' -not -name 'pstg_log' -not -name 'xrd.watchdog.log' -not -name 'apmon.log' -not -name 'servMon.log' -print)

  if [[ ! -f ${LOCK} ]]; then
    touch ${LOCK}
    for log in $not_compressed; do /usr/bin/bzip2 -9fq $log; done
    /bin/rm -f ${LOCK}
  fi

  # move compressed to logs backup
  mv -f ${XRDRUNDIR}/logs/*/*.bz2 ${XRDRUNDIR}/logsbackup/ &> /dev/null
}

######################################
execEnvironment() {
    /bin/mkdir -p ${XRDRUNDIR}/logs/
    /bin/mkdir -p ${XRDRUNDIR}/core/${USER}_$1
    /bin/mkdir -p ${XRDRUNDIR}/admin/

    ULIM_OPENF=$(ulimit -n)
    ULIM_USR_PROC=$(ulimit -u)

    ulimit -n ${XRDMAXFD}

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

    /bin/chown -R $XRDUSER ${XRDRUNDIR}/core ${XRDRUNDIR}/logs ${XRDRUNDIR}/admin
    /bin/chmod -R 755 ${XRDRUNDIR}/core ${XRDRUNDIR}/logs ${XRDRUNDIR}/admin
}

######################################
killXRD() {
    echo -n "Stopping xrootd/cmsd: "

    /usr/bin/pkill -u $USER xrootd
    /usr/bin/pkill -u $USER cmsd
    /bin/sleep 1
    /usr/bin/pkill -9 -u $USER xrootd
    /usr/bin/pkill -9 -u $USER cmsd
    /usr/bin/pkill -f -u $USER mpxstats

    echo_passed;
    echo

    echo -n "Stopping ApMon:"
    servMon -k
}

######################################
restartXRD() {
    echo restartXRD
    killXRD

    execEnvironment ${INSTANCE_NAME} || exit

    ## STARTING SERVICES WITH THE CUSTOMIZED CONFIGURATION
    echo -n "Starting xrootd [${INSTANCE_NAME}]: "
    startUp startXRDserv ${XRDCONFDIR}/xrootd.cf

    echo -n "Starting cmsd   [${INSTANCE_NAME}]: "
    startUp startCMSDserv ${XRDCONFDIR}/xrootd.cf

    startMon
    sleep 1 ## need delay for starMon
}

######################################
checkstate() {
echo "******************************************"
date
echo "******************************************"

nxrd=$(/usr/bin/pgrep -u $USER xrootd | wc -l);
ncms=$(/usr/bin/pgrep -u $USER cmsd   | wc -l);

returnval=0

if (( nxrd == nproc )); then
  echo -n "xrootd:";
  echo_success;
  echo
else
  echo -n "xrootd:";
  echo_failure;
  echo
  returnval=1;
fi

if (( ncms == nproc )) ; then
  echo -n "cmsd :";
  echo_success;
  echo
else
  echo -n "cmsd :";
  echo_failure;
  echo
  returnval=1;
fi

if [[ -n "${MONALISA_HOST}" ]] ; then
  lines=$(/bin/find ${apmonPidFile}* 2>/dev/null | /usr/bin/wc -l)

  if (( lines > 0 )) ; then
    echo -n "apmon:";
    echo_success;
    echo
  else
    echo -n "apmon:";
    echo_failure;
    echo
    returnval=1;
  fi
fi

exit $returnval
}

######################
##    Main logic    ##
######################
xrdsh_main() {
if [[ "$1" == "-c" ]]; then  ## check and restart if not running
    bootstrap
    addcron # it will remove old xrd.sh line and
    checkkeys

    ## check the number of xrootd and cmsd processes
    nxrd=$(/usr/bin/pgrep -u $USER xrootd | /usr/bin/wc -l)
    ncms=$(/usr/bin/pgrep -u $USER cmsd   | /usr/bin/wc -l)

    ## if their number is lower than it should (number given by the roles)
    if (( (nxrd < nproc) || (ncms < nproc) )) ; then
      /bin/date
      echo "------------------------------------------"
      /bin/ps
      echo "------------------------------------------"
      echo "Starting all .... (only $nxrd xrootds $ncms cmsds)"
      restartXRD
      echo "------------------------------------------"
    fi

    ## we start servMon anyway
    [[ -n "$MONALISA_HOST" ]] && servMon
    checkstate
elif [[ "$1" == "-check" ]]; then
## CLI starting of services
    bootstrap
    checkstate
elif [[ "$1" == "-f" ]]; then   ## force restart
    addcron # it will remove old xrd.sh line and
    bootstrap
    checkkeys
    /bin/date
    echo "(Re-)Starting ...."
    restartXRD

    ## we start servMon anyway
    [[ -n "$MONALISA_HOST" ]] && servMon
    checkstate
elif [[ "$1" == "-k" ]]; then  ## kill running processes
    removecron
    killXRD
    checkstate
elif [[ "$1" == "-logs" ]]; then  ## handlelogs
    handlelogs
elif [[ "$1" == "-conf" ]]; then  ## create configuration
    createconf
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
    echo " [-logs] manage the logs";
    echo " [-conf] just (re)create configuration";
    echo " [-getkeys] just get keys";
    echo " [-addcron] add/refresh cron line";
    echo " [-limits] generate limits file";
    echo "";
    echo "Environment variables:";
    echo "  XRDSH_NOWARN_ASLIB  do not warn xrd.sh is sourced"
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

set_formatters
check_prerequisites
xrdsh_main "$@"
