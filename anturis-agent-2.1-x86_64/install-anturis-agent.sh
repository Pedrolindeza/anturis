#!/bin/bash - 
set -o nounset

SILENT_MODE=0
USERNAME=
PASSWORD=
URL=

# -s             : silent mode
# -u USERNAME    : user name
# -p PASSWORD    : password
# -U SERVER_URL  : url

while getopts U:u:p:s o
do	case "$o" in
	U)  URL="$OPTARG";;
	u)  USERNAME="$OPTARG";;
	p)  PASSWORD="$OPTARG";;
	s)  SILENT_MODE=1;;
	esac
done
shift $(($OPTIND-1))

ask_yn ()
{
	local prompt=$1
	local  __ret=$2
	local def_val=$3

	if [ $SILENT_MODE -eq 1 ] ; then
		eval $__ret=$def_val
		return
	fi

	def_str="y"
	[ $def_val -eq 0 ] && def_str="n"
	while true; do
		echo $1" (y/n)"
		read -p "[$def_str]:" yn
		case $yn in
			[Yy]* ) eval $__ret=1; break;;
			[Nn]* ) eval $__ret=0; break;;
			"" ) eval $__ret=$def_val; break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

INSTALL_SCRIPT_NAME="install-anturis-agent.sh"
UNINSTALL_SCRIPT_NAME="uninstall-anturis-agent.sh"

if [ $(basename "$0") == $INSTALL_SCRIPT_NAME ] ; then
	. pkgarch
	ARCH=`uname -m`

	if [ "$PKG_ARCH" != "$ARCH" ] ; then
	  echo You are trying to install a packge of unsupported architecture $PKG_ARCH on your computer with $ARCH architecture. Please download appropriate package.
	  exit 1
	fi
fi 

if [ `id -u` -ne 0 ] ; then
  echo You should be a root to install the package.
  exit 1
fi

PRODUCT_DIR=/opt/anturis
ETC_DIR=$PRODUCT_DIR/etc
BIN_DIR=$PRODUCT_DIR/bin
LIB_DIR=$PRODUCT_DIR/lib
LOG_DIR=$PRODUCT_DIR/log
DATA_DIR=$PRODUCT_DIR/data

INITD_DIR=/etc/init.d

if which insserv >/dev/null 2>/dev/null ; then
  SVC_MGR=insserv
elif which chkconfig >/dev/null 2>/dev/null ; then
  SVC_MGR=chkconfig
elif which update-rc.d >/dev/null 2>/dev/null ; then
  SVC_MGR=update-rc.d
else
  echo "Service manager not found"
  exit 1
fi

reg_svc ()
{
	case $SVC_MGR in
		chkconfig) chkconfig anturis-agent-service reset
			;;
		insserv) insserv -f anturis-agent-service >/dev/null 2>/dev/null
			;;
		update-rc.d) update-rc.d -f anturis-agent-service start 80 2 3 5 . stop 30 0 1 6 . >/dev/null 2>/dev/null
			;;
	esac
}

unreg_svc ()
{
	case $SVC_MGR in
		chkconfig) chkconfig --del anturis-agent-service
			;;
		insserv) insserv -f -r anturis-agent-service >/dev/null 2>/dev/null
			;;
		update-rc.d) update-rc.d -f anturis-agent-service remove >/dev/null 2>/dev/null
			;;
	esac
}

check_and_make_dir ()
{
	echo creating $1...
	[ -d $1 ] || mkdir -p $1
}

copy_files ()
{
	fl=("${@}")
	for f in "${fl[@]}"
	do
		cp -f $f $PRODUCT_DIR/$f
	done
}

copy_dir ()
{
	cp -f -d -r $1/* $2
}

cloudlinux_cleanup ()
{
    ANTURIS_GID=`id -g anturis`
    SUPER_GID=`grep  "fs\\.proc_super_gid" /etc/sysctl.conf | grep -o "[0-9]\+"`

    if [ $? -eq 0 ] ; then
        if [ $SUPER_GID -eq $ANTURIS_GID ] ; then
            sed -i "/fs\\.proc_super_gid/d" /etc/sysctl.conf
            sysctl -w fs.proc_super_gid=0
        fi
    fi
}

do_uninstall ()
{
	echo uninstalling...
	$INITD_DIR/anturis-agent-service stop >/dev/null 2>/dev/null
	killall $BIN_DIR/* >/dev/null 2>/dev/null
	unreg_svc
	rm -f $INITD_DIR/anturis-agent-service >/dev/null 2>/dev/null
	[ -f /proc/sys/fs/proc_super_gid ] && cloudlinux_cleanup
	userdel anturis >/dev/null 2>/dev/null
	rm -rf $BIN_DIR/*
	rm -rf $LIB_DIR/*
	unlink $PRODUCT_DIR/$UNINSTALL_SCRIPT_NAME
}

cloudlinux_set_super_gid_to_anturis_gid ()
{
    echo "fs.proc_super_gid = $1" >> /etc/sysctl.conf
    sysctl -w fs.proc_super_gid=$1
}

cloudlinux_change_super_gid_to_anturis_gid ()
{ 
    sed -i "s/\(fs\\.proc_super_gid\s*=\s*\)[0-9]/\1$1/" /etc/sysctl.conf
    sysctl -w fs.proc_super_gid=$1
}

cloudlinux_add_anturis_uid_to_super_gid ()
{
    echo Adding anturis to super GID [$1]
    usermod -a -G $1 anturis
}

cloudlinux_setup ()
{
    ANTURIS_GID=`id -g anturis`
    SUPER_GID=`grep  "fs\\.proc_super_gid" /etc/sysctl.conf | grep -o "[0-9]\+"`

    if [ $? -eq 0 ] ; then
        if [ $SUPER_GID -eq 0 ] ; then
            cloudlinux_change_super_gid_to_anturis_gid $ANTURIS_GID
        else
            cloudlinux_add_anturis_uid_to_super_gid $SUPER_GID
        fi
    else
        cloudlinux_set_super_gid_to_anturis_gid $ANTURIS_GID
    fi
}


do_signup ()
{
	if [ $SILENT_MODE -eq 0 ] ; then
		read -p "Enter user name: " USERNAME
		read -s -p "Enter password: " PASSWORD
	fi
	$BIN_DIR/agent-config -t >/dev/null 2>/dev/null
	$BIN_DIR/agent-config -s -un="$USERNAME" -up="$PASSWORD"
        if [ -n "$URL" ] ; then
		$BIN_DIR/agent-config -s -su="$URL"            
        fi
	$BIN_DIR/agent-config -c
        sleep 5
}

do_install ()
{
	echo Installing...

	if [ -x $PRODUCT_DIR/$UNINSTALL_SCRIPT_NAME ]; then
		ask_yn "Anturis agent is already installed. Do you want to uninstall it first?" yn 1
		[ $yn -eq 0 ] && exit
		$PRODUCT_DIR/$UNINSTALL_SCRIPT_NAME
	fi

	install_daemon=0
	install_cp=0
	install_tr=0

	ask_yn "Whould you like to install Anturis agent daemon?" install_daemon 1
	if [ $install_daemon -eq 1 ]; then
		ask_yn "Whould you like to install Anturis agent control panel (requires X-Windows)?" install_cp 1
	fi

	ask_yn "Whould you like to install Anturis web transaction recorder (requires X-Windows)?" install_tr 1

	[ $install_daemon -eq 0 ] && [ $install_cp -eq 0 ] && [ $install_tr -eq 0 ] && echo "Nothing to install" && exit
	
	dirs=( $PRODUCT_DIR $BIN_DIR $ETC_DIR $LIB_DIR $LOG_DIR $DATA_DIR)
	for f in "${dirs[@]}"
	do
		check_and_make_dir $f
	done

	[ $install_tr -eq 1 ] && check_and_make_dir $LIB_DIR/imageformats

	daemon_files=( bin/agent-service bin/agent-config
		bin/plugin-httplatency2 bin/plugin-localresources2 bin/plugin-logfile2 bin/plugin-shellscript2 bin/plugin-snmp2 bin/plugin-tcp2 bin/plugin-sql2 bin/plugin-ping2 bin/plugin-apache2 bin/plugin-mbeans.jar bin/plugin-fullpage  bin/plugin-ip
		lib/libQtCore.so.4 lib/libQtSql.so.4 lib/libQtNetwork.so.4 etc/anturis-agent-service bin/smartctl)
	cp_files=( bin/agent-ui lib/libQtGui.so.4 )
	tr_files=( bin/transaction-recorder bin/plugin-httplatency2 lib/libQtCore.so.4 lib/libQtNetwork.so.4
		lib/libQtGui.so.4 lib/libQtWebKit.so.4 lib/imageformats/libqgif.so  lib/imageformats/libqico.so
		lib/imageformats/libqjpeg.so  lib/imageformats/libqmng.so  lib/imageformats/libqsvg.so  lib/imageformats/libqtiff.so)

	cp $0 $PRODUCT_DIR/$UNINSTALL_SCRIPT_NAME

	[ $install_daemon -eq 1 ] && copy_files "${daemon_files[@]}"
	[ $install_cp -eq 1 ]     && copy_files "${cp_files[@]}"
	[ $install_tr -eq 1 ]     && copy_files "${tr_files[@]}"

	#allow shared libraries text relocation if selinux is enabled
	chcon -t textrel_shlib_t /opt/anturis/lib/* >/dev/null 2>/dev/null
	chcon -t textrel_shlib_t /opt/anturis/bin/* >/dev/null 2>/dev/null

	if [ $install_daemon -eq 1 ]; then
		ln -s $PRODUCT_DIR/etc/anturis-agent-service $INITD_DIR/anturis-agent-service

		groupadd -f anturis
		useradd -g anturis anturis

		chown -R root.anturis $PRODUCT_DIR

		find $ETC_DIR -type d -exec chmod 2770 {} +
		find $ETC_DIR -type f -exec chmod 660 {} +
		touch /agent-service.ini
                chmod 640 $ETC_DIR/agent-service.ini
		chmod 750 $ETC_DIR/anturis-agent-service

		find $DATA_DIR -type d -exec chmod 2770 {} +
		find $DATA_DIR -type f -exec chmod 660 {} +
		
		find $LOG_DIR -type d -exec chmod 2770 {} +
		find $LOG_DIR -type f -exec chmod 660 {} +

		[ -f /proc/sys/fs/proc_super_gid ] && cloudlinux_setup
		reg_svc
		ask_yn "Do you want to start Anturis agent daemon now?" yn 1
		if [ $yn -eq 1 ]; then
			$INITD_DIR/anturis-agent-service start
			sleep 10
			ask_yn "Do you want to connect Anturis agent to your server account?" yn 1
			[ $yn -eq 1 ] && do_signup
		fi
	fi
}


case `basename $0` in
	$INSTALL_SCRIPT_NAME ) do_install;;
	$UNINSTALL_SCRIPT_NAME ) do_uninstall;;
esac

exit $?

