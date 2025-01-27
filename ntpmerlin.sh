#!/bin/sh

##########################################################
##         _           __  __              _  _         ##
##        | |         |  \/  |            | |(_)        ##
##  _ __  | |_  _ __  | \  / |  ___  _ __ | | _  _ __   ##
## | '_ \ | __|| '_ \ | |\/| | / _ \| '__|| || || '_ \  ##
## | | | || |_ | |_) || |  | ||  __/| |   | || || | | | ##
## |_| |_| \__|| .__/ |_|  |_| \___||_|   |_||_||_| |_| ##
##             | |                                      ##
##             |_|                                      ##
##                                                      ##
##       https://github.com/jackyaz/ntpMerlin           ##
##                                                      ##
##########################################################

#shellcheck disable=SC2019
#shellcheck disable=SC2018

### Start of script variables ###
readonly SCRIPT_NAME="ntpMerlin"
readonly SCRIPT_NAME_LOWER=$(echo $SCRIPT_NAME | tr 'A-Z' 'a-z' | sed 's/d//')
readonly SCRIPT_VERSION="v3.2.2"
SCRIPT_BRANCH="master"
SCRIPT_REPO="https://raw.githubusercontent.com/jackyaz/$SCRIPT_NAME/$SCRIPT_BRANCH"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME_LOWER.d"
readonly SCRIPT_WEBPAGE_DIR="$(readlink /www/user)"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME_LOWER"
readonly SHARED_DIR="/jffs/addons/shared-jy"
readonly SHARED_REPO="https://raw.githubusercontent.com/jackyaz/shared-jy/master"
readonly SHARED_WEB_DIR="$SCRIPT_WEBPAGE_DIR/shared-jy"
[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH=/opt/bin/sqlite3 || SQLITE3_PATH=/usr/sbin/sqlite3
### End of script variables ###

### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"
### End of output format variables ###

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	fi
}

Firmware_Version_Check(){
	if nvram get rc_support | grep -qF "am_addons"; then
		return 0
	else
		return 1
	fi
}

### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock(){
	if [ -f "/tmp/$SCRIPT_NAME.lock" ]; then
		ageoflock=$(($(date +%s) - $(date +%s -r /tmp/$SCRIPT_NAME.lock)))
		if [ "$ageoflock" -gt 600 ]; then
			Print_Output true "Stale lock file found (>600 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$SCRIPT_NAME.lock)" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$SCRIPT_NAME.lock"
			return 0
		else
			Print_Output true "Lock file found (age: $ageoflock seconds) - stopping to prevent duplicate runs" "$ERR"
			if [ -z "$1" ]; then
				exit 1
			else
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/$SCRIPT_NAME.lock"
		return 0
	fi
}

Clear_Lock(){
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
}
############################################################################

Set_Version_Custom_Settings(){
	SETTINGSFILE=/jffs/addons/custom_settings.txt
	case "$1" in
		local)
			if [ -f "$SETTINGSFILE" ]; then
				if [ "$(grep -c "ntpmerlin_version_local" $SETTINGSFILE)" -gt 0 ]; then
					if [ "$SCRIPT_VERSION" != "$(grep "ntpmerlin_version_local" /jffs/addons/custom_settings.txt | cut -f2 -d' ')" ]; then
						sed -i "s/ntpmerlin_version_local.*/ntpmerlin_version_local $SCRIPT_VERSION/" "$SETTINGSFILE"
					fi
				else
					echo "ntpmerlin_version_local $SCRIPT_VERSION" >> "$SETTINGSFILE"
				fi
			else
				echo "ntpmerlin_version_local $SCRIPT_VERSION" >> "$SETTINGSFILE"
			fi
		;;
		server)
			if [ -f "$SETTINGSFILE" ]; then
				if [ "$(grep -c "ntpmerlin_version_server" $SETTINGSFILE)" -gt 0 ]; then
					if [ "$2" != "$(grep "ntpmerlin_version_server" /jffs/addons/custom_settings.txt | cut -f2 -d' ')" ]; then
						sed -i "s/ntpmerlin_version_server.*/ntpmerlin_version_server $2/" "$SETTINGSFILE"
					fi
				else
					echo "ntpmerlin_version_server $2" >> "$SETTINGSFILE"
				fi
			else
				echo "ntpmerlin_version_server $2" >> "$SETTINGSFILE"
			fi
		;;
	esac
}

Update_Check(){
	echo 'var updatestatus = "InProgress";' > "$SCRIPT_WEB_DIR/detect_update.js"
	doupdate="false"
	localver=$(grep "SCRIPT_VERSION=" /jffs/scripts/"$SCRIPT_NAME_LOWER" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" | grep -qF "jackyaz" || { Print_Output true "404 error detected - stopping update" "$ERR"; return 1; }
	serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	if [ "$localver" != "$serverver" ]; then
		doupdate="version"
		Set_Version_Custom_Settings server "$serverver"
		echo 'var updatestatus = "'"$serverver"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	else
		localmd5="$(md5sum "/jffs/scripts/$SCRIPT_NAME_LOWER" | awk '{print $1}')"
		remotemd5="$(curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" | md5sum | awk '{print $1}')"
		if [ "$localmd5" != "$remotemd5" ]; then
			doupdate="md5"
			Set_Version_Custom_Settings server "$serverver-hotfix"
			echo 'var updatestatus = "'"$serverver-hotfix"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
		fi
	fi
	if [ "$doupdate" = "false" ]; then
		echo 'var updatestatus = "None";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	fi
	echo "$doupdate,$localver,$serverver"
}

Update_Version(){
	if [ -z "$1" ] || [ "$1" = "unattended" ]; then
		updatecheckresult="$(Update_Check)"
		isupdate="$(echo "$updatecheckresult" | cut -f1 -d',')"
		localver="$(echo "$updatecheckresult" | cut -f2 -d',')"
		serverver="$(echo "$updatecheckresult" | cut -f3 -d',')"
		
		if [ "$isupdate" = "version" ]; then
			Print_Output true "New version of $SCRIPT_NAME available - updating to $serverver" "$PASS"
		elif [ "$isupdate" = "md5" ]; then
			Print_Output true "MD5 hash of $SCRIPT_NAME does not match - downloading updated $serverver" "$PASS"
		fi
		
		Update_File shared-jy.tar.gz
		
		if [ "$isupdate" != "false" ]; then
			Update_File timeserverd
			TIMESERVER_NAME="$(TimeServer check)"
			if [ "$TIMESERVER_NAME" = "ntpd" ]; then
				Update_File S77ntpd
				Update_File ntp.conf
			elif [ "$TIMESERVER_NAME" = "chronyd" ]; then
				Update_File S77chronyd
				Update_File chrony.conf
			fi
			
			Update_File ntpdstats_www.asp
			
			/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" -o "/jffs/scripts/$SCRIPT_NAME_LOWER" && Print_Output true "$SCRIPT_NAME successfully updated"
			chmod 0755 /jffs/scripts/"$SCRIPT_NAME_LOWER"
			Clear_Lock
			if [ -z "$1" ]; then
				exec "$0" setversion
			elif [ "$1" = "unattended" ]; then
				exec "$0" setversion unattended
			fi
			exit 0
		else
			Print_Output true "No new version - latest is $localver" "$WARN"
			Clear_Lock
		fi
	fi
	
	if [ "$1" = "force" ]; then
		serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		Print_Output true "Downloading latest version ($serverver) of $SCRIPT_NAME" "$PASS"
		Update_File timeserverd
		TIMESERVER_NAME="$(TimeServer check)"
		if [ "$TIMESERVER_NAME" = "ntpd" ]; then
			Update_File ntp.conf
			Update_File S77ntpd
		elif [ "$TIMESERVER_NAME" = "chronyd" ]; then
			Update_File chrony.conf
			Update_File S77chronyd
		fi
		Update_File ntpdstats_www.asp
		Update_File shared-jy.tar.gz
		/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER.sh" -o "/jffs/scripts/$SCRIPT_NAME_LOWER" && Print_Output true "$SCRIPT_NAME successfully updated"
		chmod 0755 /jffs/scripts/"$SCRIPT_NAME_LOWER"
		Clear_Lock
		if [ -z "$2" ]; then
			exec "$0" setversion
		elif [ "$2" = "unattended" ]; then
			exec "$0" setversion unattended
		fi
		exit 0
	fi
}

Update_File(){
	if [ "$1" = "S77ntpd" ] || [ "$1" = "S77chronyd" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if ! diff -q "$tmpfile" "/opt/etc/init.d/$1" >/dev/null 2>&1; then
			Print_Output true "New version of $1 downloaded" "$PASS"
			TimeServer_Customise
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "ntp.conf" ] || [ "$1" = "chrony.conf" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if [ ! -f "$SCRIPT_STORAGE_DIR/$1" ]; then
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1"
			Print_Output true "$SCRIPT_STORAGE_DIR/$1 does not exist, downloading now." "$PASS"
		elif [ -f "$SCRIPT_STORAGE_DIR/$1.default" ]; then
			if ! diff -q "$tmpfile" "$SCRIPT_STORAGE_DIR/$1.default" >/dev/null 2>&1; then
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
				Print_Output true "New default version of $1 downloaded to $SCRIPT_STORAGE_DIR/$1.default, please compare against your $SCRIPT_STORAGE_DIR/$1" "$PASS"
			fi
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
			Print_Output true "$SCRIPT_STORAGE_DIR/$1.default does not exist, downloading now. Please compare against your $SCRIPT_STORAGE_DIR/$1" "$PASS"
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "ntpdstats_www.asp" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if [ -f "$SCRIPT_DIR/$1" ]; then
			if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
				Get_WebUI_Page "$SCRIPT_DIR/$1"
				sed -i "\\~$MyPage~d" /tmp/menuTree.js
				rm -f "$SCRIPT_WEBPAGE_DIR/$MyPage" 2>/dev/null
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
				Print_Output true "New version of $1 downloaded" "$PASS"
				Mount_WebUI
			fi
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
			Mount_WebUI
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "timeserverd" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			chmod 0755 "$SCRIPT_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
			TimeServer_Customise
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "shared-jy.tar.gz" ]; then
		if [ ! -f "$SHARED_DIR/$1.md5" ]; then
			Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
			Download_File "$SHARED_REPO/$1.md5" "$SHARED_DIR/$1.md5"
			tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
			rm -f "$SHARED_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
		else
			localmd5="$(cat "$SHARED_DIR/$1.md5")"
			remotemd5="$(curl -fsL --retry 3 "$SHARED_REPO/$1.md5")"
			if [ "$localmd5" != "$remotemd5" ]; then
				Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
				Download_File "$SHARED_REPO/$1.md5" "$SHARED_DIR/$1.md5"
				tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
				rm -f "$SHARED_DIR/$1"
				Print_Output true "New version of $1 downloaded" "$PASS"
			fi
		fi
	else
		return 1
	fi
}

Validate_Number(){
	if [ "$2" -eq "$2" ] 2>/dev/null; then
		return 0
	else
		formatted="$(echo "$1" | sed -e 's/|/ /g')"
		if [ -z "$3" ]; then
			Print_Output false "$formatted - $2 is not a number" "$ERR"
		fi
		return 1
	fi
}

Conf_FromSettings(){
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	TMPFILE="/tmp/ntpmerlin_settings.txt"
	if [ -f "$SETTINGSFILE" ]; then
		if [ "$(grep "ntpmerlin_" $SETTINGSFILE | grep -v "version" -c)" -gt 0 ]; then
			Print_Output true "Updated settings from WebUI found, merging into $SCRIPT_CONF" "$PASS"
			cp -a "$SCRIPT_CONF" "$SCRIPT_CONF.bak"
			grep "ntpmerlin_" "$SETTINGSFILE" | grep -v "version" > "$TMPFILE"
			sed -i "s/ntpmerlin_//g;s/ /=/g" "$TMPFILE"
			while IFS='' read -r line || [ -n "$line" ]; do
				SETTINGNAME="$(echo "$line" | cut -f1 -d'=' | awk '{ print toupper($1) }')"
				SETTINGVALUE="$(echo "$line" | cut -f2 -d'=')"
				sed -i "s/$SETTINGNAME=.*/$SETTINGNAME=$SETTINGVALUE/" "$SCRIPT_CONF"
			done < "$TMPFILE"
			grep 'ntpmerlin_version' "$SETTINGSFILE" > "$TMPFILE"
			sed -i "\\~ntpmerlin_~d" "$SETTINGSFILE"
			mv "$SETTINGSFILE" "$SETTINGSFILE.bak"
			cat "$SETTINGSFILE.bak" "$TMPFILE" > "$SETTINGSFILE"
			rm -f "$TMPFILE"
			rm -f "$SETTINGSFILE.bak"
			
			ScriptStorageLocation "$(ScriptStorageLocation check)"
			Create_Symlinks
			
			Generate_CSVs
			
			TimeServer "$(TimeServer check)"
			
			Print_Output true "Merge of updated settings from WebUI completed successfully" "$PASS"
		else
			Print_Output false "No updated settings from WebUI found, no merge into $SCRIPT_CONF necessary" "$PASS"
		fi
	fi
}

Create_Dirs(){
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi
	
	if [ ! -d "$SCRIPT_STORAGE_DIR" ]; then
		mkdir -p "$SCRIPT_STORAGE_DIR"
	fi
	
	if [ ! -d "$CSV_OUTPUT_DIR" ]; then
		mkdir -p "$CSV_OUTPUT_DIR"
	fi
	
	if [ ! -d "$SHARED_DIR" ]; then
		mkdir -p "$SHARED_DIR"
	fi
	
	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi
	
	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi
}

Create_Symlinks(){
	rm -rf "${SCRIPT_WEB_DIR:?}/"* 2>/dev/null
	
	ln -s /tmp/detect_ntpmerlin.js "$SCRIPT_WEB_DIR/detect_ntpmerlin.js" 2>/dev/null
	ln -s "$SCRIPT_STORAGE_DIR/ntpstatstext.js" "$SCRIPT_WEB_DIR/ntpstatstext.js" 2>/dev/null
	
	ln -s "$SCRIPT_CONF" "$SCRIPT_WEB_DIR/config.htm" 2>/dev/null
	
	ln -s "$CSV_OUTPUT_DIR" "$SCRIPT_WEB_DIR/csv" 2>/dev/null
	
	if [ ! -d "$SHARED_WEB_DIR" ]; then
		ln -s "$SHARED_DIR" "$SHARED_WEB_DIR" 2>/dev/null
	fi
}

Conf_Exists(){
	if [ -f "$SCRIPT_CONF" ]; then
		dos2unix "$SCRIPT_CONF"
		chmod 0644 "$SCRIPT_CONF"
		sed -i -e 's/"//g' "$SCRIPT_CONF"
		if [ "$(wc -l < "$SCRIPT_CONF")" -eq 1 ]; then
			echo "OUTPUTTIMEMODE=unix" >> "$SCRIPT_CONF"
		fi
		if [ "$(wc -l < "$SCRIPT_CONF")" -eq 2 ]; then
			echo "STORAGELOCATION=jffs" >> "$SCRIPT_CONF"
		fi
		if [ "$(wc -l < "$SCRIPT_CONF")" -eq 3 ]; then
			echo "TIMESERVER=ntpd" >> "$SCRIPT_CONF"
		fi
		return 0
	else
		{ echo "OUTPUTDATAMODE=raw"; echo "OUTPUTTIMEMODE=unix"; echo "STORAGELOCATION=jffs"; echo "TIMESERVER=ntpd"; } > "$SCRIPT_CONF"
		return 1
	fi
}

Auto_ServiceEvent(){
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				# shellcheck disable=SC2016
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME_LOWER service_event"' "$@" & # '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					# shellcheck disable=SC2016
					echo "/jffs/scripts/$SCRIPT_NAME_LOWER service_event"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event
				echo "" >> /jffs/scripts/service-event
				# shellcheck disable=SC2016
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER service_event"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}

Auto_DNSMASQ(){
	case $1 in
		create)
			if [ -f /jffs/configs/dnsmasq.conf.add ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/configs/dnsmasq.conf.add)
				# shellcheck disable=SC2016
				STARTUPLINECOUNTEX=$(grep -cx "dhcp-option=lan,42,$(nvram get lan_ipaddr)"' # '"$SCRIPT_NAME" /jffs/configs/dnsmasq.conf.add)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/configs/dnsmasq.conf.add
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					# shellcheck disable=SC2016
					echo "dhcp-option=lan,42,$(nvram get lan_ipaddr)"' # '"$SCRIPT_NAME" >> /jffs/configs/dnsmasq.conf.add
					service restart_dnsmasq >/dev/null 2>&1
				fi
			else
				echo "" >> /jffs/configs/dnsmasq.conf.add
				# shellcheck disable=SC2016
				echo "dhcp-option=lan,42,$(nvram get lan_ipaddr)"' # '"$SCRIPT_NAME" >> /jffs/configs/dnsmasq.conf.add
				chmod 0644 /jffs/configs/dnsmasq.conf.add
				service restart_dnsmasq >/dev/null 2>&1
			fi
		;;
		delete)
			if [ -f /jffs/configs/dnsmasq.conf.add ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/configs/dnsmasq.conf.add)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/configs/dnsmasq.conf.add
					service restart_dnsmasq >/dev/null 2>&1
				fi
			fi
		;;
	esac
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi
			fi
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/post-mount
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/post-mount
				echo "" >> /jffs/scripts/post-mount
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/post-mount
				chmod 0755 /jffs/scripts/post-mount
			fi
		;;
		delete)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi
			fi
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
				fi
			fi
		;;
	esac
}

Auto_NAT(){
	case $1 in
		create)
			if [ -f /jffs/scripts/nat-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/nat-start)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME_LOWER ntpredirect"' # '"$SCRIPT_NAME" /jffs/scripts/nat-start)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/nat-start
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "/jffs/scripts/$SCRIPT_NAME_LOWER ntpredirect"' # '"$SCRIPT_NAME" >> /jffs/scripts/nat-start
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/nat-start
				echo "" >> /jffs/scripts/nat-start
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER ntpredirect"' # '"$SCRIPT_NAME" >> /jffs/scripts/nat-start
				chmod 0755 /jffs/scripts/nat-start
			fi
		;;
		delete)
			if [ -f /jffs/scripts/nat-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/nat-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/nat-start
				fi
			fi
		;;
		check)
			if [ -f /jffs/scripts/nat-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/nat-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					return 0
				else
					return 1
				fi
			else
				return 1
			fi
		;;
	esac
}

Auto_Cron(){
	case $1 in
		create)
			STARTUPLINECOUNT=$(cru l | grep -c "$SCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$SCRIPT_NAME" "*/10 * * * * /jffs/scripts/$SCRIPT_NAME_LOWER generate"
			fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "$SCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$SCRIPT_NAME"
			fi
		;;
	esac
}

Download_File(){
	/usr/sbin/curl -fsL --retry 3 "$1" -o "$2"
}

NTP_Redirect(){
	case $1 in
		create)
			iptables -t nat -D PREROUTING -i br0 -p udp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)" 2>/dev/null
			iptables -t nat -D PREROUTING -i br0 -p tcp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)" 2>/dev/null
			iptables -t nat -A PREROUTING -i br0 -p udp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)"
			iptables -t nat -A PREROUTING -i br0 -p tcp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)"
			Auto_DNSMASQ create 2>/dev/null
		;;
		delete)
			iptables -t nat -D PREROUTING -i br0 -p udp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)" 2>/dev/null
			iptables -t nat -D PREROUTING -i br0 -p tcp --dport 123 -j DNAT --to "$(nvram get lan_ipaddr)" 2>/dev/null
			Auto_DNSMASQ delete 2>/dev/null
		;;
	esac
}

NTP_Firmware_Check(){
	ENABLED_NTPD="$(nvram get ntpd_enable)"
	if ! Validate_Number "" "$ENABLED_NTPD" silent; then ENABLED_NTPD=0; fi
	
	if [ "$ENABLED_NTPD" -eq 1 ]; then
		Print_Output true "Built-in ntpd is enabled and will conflict, it will be disabled" "$WARN"
		nvram set ntpd_enable=0
		nvram set ntpd_server_redir=0
		nvram commit
		service restart_ntpd
		service restart_firewall
		return 1
	else
		return 0
	fi
}

Get_WebUI_Page(){
	MyPage="none"
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		page="/www/user/user$i.asp"
		if [ -f "$page" ] && [ "$(md5sum < "$1")" = "$(md5sum < "$page")" ]; then
			MyPage="user$i.asp"
			return
		elif [ "$MyPage" = "none" ] && [ ! -f "$page" ]; then
			MyPage="user$i.asp"
		fi
	done
}

### locking mechanism code credit to Martineau (@MartineauUK) ###
Mount_WebUI(){
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/ntpdstats_www.asp"
	if [ "$MyPage" = "none" ]; then
		Print_Output true "Unable to mount $SCRIPT_NAME WebUI page, exiting" "$CRIT"
		flock -u "$FD"
		return 1
	fi
	
	cp -f "$SCRIPT_DIR/ntpdstats_www.asp" "$SCRIPT_WEBPAGE_DIR/$MyPage"
	echo "ntpMerlin" > "$SCRIPT_WEBPAGE_DIR/$(echo $MyPage | cut -f1 -d'.').title"
	
	if [ "$(uname -o)" = "ASUSWRT-Merlin" ]; then
		if [ ! -f /tmp/index_style.css ]; then
			cp -f /www/index_style.css /tmp/
		fi
		
		if ! grep -q '.menu_Addons' /tmp/index_style.css ; then
			echo ".menu_Addons { background: url(ext/shared-jy/addons.png); }" >> /tmp/index_style.css
		fi
		
		umount /www/index_style.css 2>/dev/null
		mount -o bind /tmp/index_style.css /www/index_style.css
		
		if [ ! -f /tmp/menuTree.js ]; then
			cp -f /www/require/modules/menuTree.js /tmp/
		fi
		
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		
		if ! grep -q 'menuName: "Addons"' /tmp/menuTree.js ; then
			lineinsbefore="$(( $(grep -n "exclude:" /tmp/menuTree.js | cut -f1 -d':') - 1))"
			sed -i "$lineinsbefore"'i,\n{\nmenuName: "Addons",\nindex: "menu_Addons",\ntab: [\n{url: "ext/shared-jy/redirect.htm", tabName: "Help & Support"},\n{url: "NULL", tabName: "__INHERIT__"}\n]\n}' /tmp/menuTree.js
		fi
		
		if ! grep -q "javascript:window.open('/ext/shared-jy/redirect.htm'" /tmp/menuTree.js ; then
			sed -i "s~ext/shared-jy/redirect.htm~javascript:window.open('/ext/shared-jy/redirect.htm','_blank')~" /tmp/menuTree.js
		fi
		sed -i "/url: \"javascript:window.open('\/ext\/shared-jy\/redirect.htm'/i {url: \"$MyPage\", tabName: \"ntpMerlin\"}," /tmp/menuTree.js
		
		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	fi
	flock -u "$FD"
	Print_Output true "Mounted $SCRIPT_NAME WebUI page as $MyPage" "$PASS"
}

TimeServer_Customise(){
	TIMESERVER_NAME="$(TimeServer check)"
	if [ -f "/opt/etc/init.d/S77$TIMESERVER_NAME" ]; then
		"/opt/etc/init.d/S77$TIMESERVER_NAME" stop >/dev/null 2>&1
	fi
	rm -f "/opt/etc/init.d/S77$TIMESERVER_NAME"
	Download_File "$SCRIPT_REPO/S77$TIMESERVER_NAME" "/opt/etc/init.d/S77$TIMESERVER_NAME"
	chmod +x "/opt/etc/init.d/S77$TIMESERVER_NAME"
	if [ "$TIMESERVER_NAME" = "chronyd" ]; then
		mkdir -p /opt/var/lib/chrony
		mkdir -p /opt/var/run/chrony
		chown -R nobody:nobody /opt/var/lib/chrony
		chown -R nobody:nobody /opt/var/run/chrony
		chmod -R 770 /opt/var/lib/chrony
		chmod -R 770 /opt/var/run/chrony
	fi
	"/opt/etc/init.d/S77$TIMESERVER_NAME" start >/dev/null 2>&1
}

ScriptStorageLocation(){
	case "$1" in
		usb)
			TIMESERVER_NAME="$(TimeServer check)"
			sed -i 's/^STORAGELOCATION.*$/STORAGELOCATION=usb/' "$SCRIPT_CONF"
			mkdir -p "/opt/share/$SCRIPT_NAME_LOWER.d/"
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/csv" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/config" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/config.bak" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/ntpstatstext.js" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/ntpdstats.db" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/ntp.conf" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/ntp.conf.default" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/chrony.conf" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/jffs/addons/$SCRIPT_NAME_LOWER.d/chrony.conf.default" "/opt/share/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			"/opt/etc/init.d/S77$TIMESERVER_NAME" restart >/dev/null 2>&1
			SCRIPT_CONF="/opt/share/$SCRIPT_NAME_LOWER.d/config"
			ScriptStorageLocation load
		;;
		jffs)
			TIMESERVER_NAME="$(TimeServer check)"
			sed -i 's/^STORAGELOCATION.*$/STORAGELOCATION=jffs/' "$SCRIPT_CONF"
			mkdir -p "/jffs/addons/$SCRIPT_NAME_LOWER.d/"
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/csv" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/config" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/config.bak" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/ntpstatstext.js" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/ntpdstats.db" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/ntp.conf" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/ntp.conf.default" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/chrony.conf" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			mv "/opt/share/$SCRIPT_NAME_LOWER.d/chrony.conf.default" "/jffs/addons/$SCRIPT_NAME_LOWER.d/" 2>/dev/null
			"/opt/etc/init.d/S77$TIMESERVER_NAME" restart >/dev/null 2>&1
			SCRIPT_CONF="/jffs/addons/$SCRIPT_NAME_LOWER.d/config"
			ScriptStorageLocation load
		;;
		check)
			STORAGELOCATION=$(grep "STORAGELOCATION" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$STORAGELOCATION"
		;;
		load)
			STORAGELOCATION=$(grep "STORAGELOCATION" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$STORAGELOCATION" = "usb" ]; then
				SCRIPT_STORAGE_DIR="/opt/share/$SCRIPT_NAME_LOWER.d"
			elif [ "$STORAGELOCATION" = "jffs" ]; then
				SCRIPT_STORAGE_DIR="/jffs/addons/$SCRIPT_NAME_LOWER.d"
			fi
			
			CSV_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/csv"
		;;
	esac
}

OutputDataMode(){
	case "$1" in
		raw)
			sed -i 's/^OUTPUTDATAMODE.*$/OUTPUTDATAMODE=raw/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		average)
			sed -i 's/^OUTPUTDATAMODE.*$/OUTPUTDATAMODE=average/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		check)
			OUTPUTDATAMODE=$(grep "OUTPUTDATAMODE" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$OUTPUTDATAMODE"
		;;
	esac
}

OutputTimeMode(){
	case "$1" in
		unix)
			sed -i 's/^OUTPUTTIMEMODE.*$/OUTPUTTIMEMODE=unix/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		non-unix)
			sed -i 's/^OUTPUTTIMEMODE.*$/OUTPUTTIMEMODE=non-unix/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		check)
			OUTPUTTIMEMODE=$(grep "OUTPUTTIMEMODE" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$OUTPUTTIMEMODE"
		;;
	esac
}

TimeServer(){
	case "$1" in
		ntpd)
			sed -i 's/^TIMESERVER.*$/TIMESERVER=ntpd/' "$SCRIPT_CONF"
			/opt/etc/init.d/S77chronyd stop >/dev/null 2>&1
			rm -f /opt/etc/init.d/S77chronyd
			if [ ! -f /opt/sbin/ntpd ]; then
				opkg update
				opkg install ntp-utils
				opkg install ntpd
			fi
			Update_File ntp.conf >/dev/null 2>&1
			Update_File S77ntpd >/dev/null 2>&1
		;;
		chronyd)
			sed -i 's/^TIMESERVER.*$/TIMESERVER=chronyd/' "$SCRIPT_CONF"
			/opt/etc/init.d/S77ntpd stop >/dev/null 2>&1
			rm -f /opt/etc/init.d/S77ntpd
			if [ ! -f /opt/sbin/chronyd ]; then
				opkg update
				opkg install chrony
			fi
			Update_File chrony.conf >/dev/null 2>&1
			Update_File S77chronyd >/dev/null 2>&1
		;;
		check)
			TIMESERVER=$(grep "TIMESERVER" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$TIMESERVER"
		;;
	esac
}

WriteStats_ToJS(){
	echo "function $3(){" > "$2"
	html='document.getElementById("'"$4"'").innerHTML="'
	while IFS='' read -r line || [ -n "$line" ]; do
		html="${html}${line}\\r\\n"
	done < "$1"
	html="$html"'"'
	printf "%s\\r\\n}\\r\\n" "$html" >> "$2"
}

#$1 fieldname $2 tablename $3 frequency (hours) $4 length (days) $5 outputfile $6 outputfrequency $7 sqlfile $8 timestamp
WriteSql_ToFile(){
	timenow="$8"
	maxcount="$(echo "$3" "$4" | awk '{printf ((24*$2)/$1)}')"
	multiplier="$(echo "$3" | awk '{printf (60*60*$1)}')"
	
	{
		echo ".mode csv"
		echo ".headers on"
		echo ".output $5$6.htm"
	} >> "$7"
	
	echo "SELECT '$1' Metric, Min([Timestamp]) Time, IFNULL(Avg(printf('%f', $1)),'NaN') Value FROM $2 WHERE ([Timestamp] >= $timenow - ($multiplier*$maxcount)) GROUP BY ([Timestamp]/($multiplier));" >> "$7"
}

Get_TimeServer_Stats(){
	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	NTP_Firmware_Check
	ScriptStorageLocation load
	Create_Symlinks
	
	echo 'var ntpstatus = "InProgress";' > /tmp/detect_ntpmerlin.js
	
	#shellcheck disable=SC2086
	killall ntp 2>/dev/null
	
	TIMESERVER="$(TimeServer check)"
	if [ "$TIMESERVER" = "ntpd" ]; then
		tmpfile=/tmp/ntp-stats.$$
		ntpq -4 -c rv | awk 'BEGIN{ RS=","}{ print }' > "$tmpfile"
		
		[ -n "$(grep offset "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] && NOFFSET=$(grep offset "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NOFFSET=0
		[ -n "$(grep frequency "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] && NFREQ=$(grep frequency "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NFREQ=0
		[ -n "$(grep sys_jitter "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] && NSJIT=$(grep sys_jitter "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NSJIT=0
		[ -n "$(grep clk_jitter "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] && NCJIT=$(grep clk_jitter "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NCJIT=0
		[ -n "$(grep clk_wander "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] && NWANDER=$(grep clk_wander "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NWANDER=0
		[ -n "$(grep rootdisp "$tmpfile" | awk 'BEGIN{FS="="}{print $2}')" ] &&  NDISPER=$(grep rootdisp "$tmpfile" | awk 'BEGIN{FS="="}{print $2}') || NDISPER=0
		rm -f "$tmpfile"
	elif [ "$TIMESERVER" = "chronyd" ]; then
		tmpfile=/tmp/chrony-stats.$$
		chronyc tracking > "$tmpfile"
		
		[ -n "$(grep "Last offset" "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}')" ] && NOFFSET=$(grep Last "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}') || NOFFSET=0
		[ -n "$(grep Frequency "$tmpfile" | awk 'BEGIN{FS=" "}{print $3}')" ] && NFREQ=$(grep Frequency "$tmpfile" | awk 'BEGIN{FS=" "}{print $3}') || NFREQ=0
		[ -n "$(grep System "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}')" ] && NSJIT=$(grep System "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}') || NSJIT=0
		[ -n "$(grep Skew "$tmpfile" | awk 'BEGIN{FS=" "}{print $3}')" ] && NWANDER=$(grep Skew "$tmpfile" | awk 'BEGIN{FS=" "}{print $3}') || NWANDER=0
		[ -n "$(grep dispersion "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}')" ] && NDISPER=$(grep dispersion "$tmpfile" | awk 'BEGIN{FS=" "}{print $4}') || NDISPER=0
		
		NOFFSET="$(echo "$NOFFSET" | awk '{printf ($1*1000)}')"
		NSJIT="$(echo "$NSJIT" | awk '{printf ($1*1000)}')"
		NCJIT="0"
		NDISPER="$(echo "$NDISPER" | awk '{printf ($1*1000)}')"
		rm -f "$tmpfile"
	fi
	
	TZ=$(cat /etc/TZ)
	export TZ
	timenow=$(date +"%s")
	timenowfriendly=$(date +"%c")
	
	Process_Upgrade
	
	{
		echo "CREATE TABLE IF NOT EXISTS [ntpstats] ([StatID] INTEGER PRIMARY KEY NOT NULL, [Timestamp] NUMERIC NOT NULL, [Offset] REAL NOT NULL,[Frequency] REAL NOT NULL,[Sys_Jitter] REAL NOT NULL,[Clk_Jitter] REAL NOT NULL,[Clk_Wander] REAL NOT NULL,[Rootdisp] REAL NOT NULL);"
		echo "INSERT INTO ntpstats ([Timestamp],[Offset],[Frequency],[Sys_Jitter],[Clk_Jitter],[Clk_Wander],[Rootdisp]) values($timenow,$NOFFSET,$NFREQ,$NSJIT,$NCJIT,$NWANDER,$NDISPER);"
	} > /tmp/ntp-stats.sql
	"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
	
	echo "DELETE FROM [ntpstats] WHERE [Timestamp] < ($timenow - (86400*30));" > /tmp/ntp-stats.sql
	"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
	rm -f /tmp/ntp-stats.sql
	
	Generate_CSVs
	
	echo "Stats last updated: $timenowfriendly" > /tmp/ntpstatstitle.txt
	WriteStats_ToJS /tmp/ntpstatstitle.txt "$SCRIPT_STORAGE_DIR/ntpstatstext.js" SetNTPDStatsTitle statstitle
	
	echo 'var ntpstatus = "Done";' > /tmp/detect_ntpmerlin.js
	
	rm -f /tmp/ntpstatstitle.txt
}

Generate_CSVs(){
	rm -f "$CSV_OUTPUT_DIR/Sys_Jitter"*
	rm -f "$CSV_OUTPUT_DIR/Frequency"*
	
	OUTPUTDATAMODE="$(OutputDataMode check)"
	OUTPUTTIMEMODE="$(OutputTimeMode check)"
	TZ=$(cat /etc/TZ)
	export TZ
	timenow=$(date +"%s")
	timenowfriendly=$(date +"%c")
	
	metriclist="Offset Frequency"
	
	for metric in $metriclist; do
		FILENAME="$metric"
		if [ "$metric" = "Frequency" ]; then
			FILENAME="Drift"
		fi
		{
			echo ".mode csv"
			echo ".headers on"
			echo ".output $CSV_OUTPUT_DIR/${FILENAME}daily.htm"
			echo "SELECT '$metric' Metric,[Timestamp] Time,printf('%f', $metric) Value FROM ntpstats WHERE [Timestamp] >= ($timenow - 86400);"
		} > /tmp/ntp-stats.sql
		
		"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
		rm -f /tmp/ntp-stats.sql
		
		if [ "$OUTPUTDATAMODE" = "raw" ]; then
			{
				echo ".mode csv"
				echo ".headers on"
				echo ".output $CSV_OUTPUT_DIR/${FILENAME}weekly.htm"
				echo "SELECT '$metric' Metric,[Timestamp] Time,printf('%f', $metric) Value FROM ntpstats WHERE [Timestamp] >= ($timenow - 86400*7);"
			} > /tmp/ntp-stats.sql
			"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
			rm -f /tmp/ntp-stats.sql
			
			{
				echo ".mode csv"
				echo ".headers on"
				echo ".output $CSV_OUTPUT_DIR/${FILENAME}monthly.htm"
				echo "SELECT '$metric' Metric,[Timestamp] Time,printf('%f', $metric) Value FROM ntpstats WHERE [Timestamp] >= ($timenow - 86400*30);"
			} > /tmp/ntp-stats.sql
			"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
			rm -f /tmp/ntp-stats.sql
		elif [ "$OUTPUTDATAMODE" = "average" ]; then
			WriteSql_ToFile "$metric" ntpstats 1 7 "$CSV_OUTPUT_DIR/$FILENAME" weekly /tmp/ntp-stats.sql "$timenow"
			"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
			rm -f /tmp/ntp-stats.sql
			
			WriteSql_ToFile "$metric" ntpstats 3 30 "$CSV_OUTPUT_DIR/$FILENAME" monthly /tmp/ntp-stats.sql "$timenow"
			"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql
			rm -f /tmp/ntp-stats.sql
		fi
	done
	
	rm -f /tmp/ntp-stats.sql
	
	{
		echo ".mode csv"
		echo ".headers on"
		echo ".output $CSV_OUTPUT_DIR/CompleteResults.htm"
	} > /tmp/ntp-complete.sql
	echo "SELECT [Timestamp],[Offset],[Frequency],[Sys_Jitter],[Clk_Jitter],[Clk_Wander],[Rootdisp] FROM ntpstats WHERE [Timestamp] >= ($timenow - 86400*30) ORDER BY [Timestamp] DESC;" >> /tmp/ntp-complete.sql
	"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-complete.sql
	rm -f /tmp/ntp-complete.sql
	
	dos2unix "$CSV_OUTPUT_DIR/"*.htm
	
	tmpoutputdir="/tmp/${SCRIPT_NAME_LOWER}results"
	mkdir -p "$tmpoutputdir"
	mv "$CSV_OUTPUT_DIR/CompleteResults.htm" "$tmpoutputdir/CompleteResults.htm"
	
	if [ "$OUTPUTTIMEMODE" = "unix" ]; then
		find "$tmpoutputdir/" -name '*.htm' -exec sh -c 'i="$1"; mv -- "$i" "${i%.htm}.csv"' _ {} \;
	elif [ "$OUTPUTTIMEMODE" = "non-unix" ]; then
		for i in "$tmpoutputdir/"*".htm"; do
			awk -F"," 'NR==1 {OFS=","; print} NR>1 {OFS=","; $1=strftime("%Y-%m-%d %H:%M:%S", $1); print }' "$i" > "$i.out"
		done
		
		find "$tmpoutputdir/" -name '*.htm.out' -exec sh -c 'i="$1"; mv -- "$i" "${i%.htm.out}.csv"' _ {} \;
		rm -f "$tmpoutputdir/"*.htm
	fi
	
	mv "$tmpoutputdir/CompleteResults.csv" "$CSV_OUTPUT_DIR/CompleteResults.htm"
	rm -f "$CSV_OUTPUT_DIR/ntpmerlindata.zip"
	rm -rf "$tmpoutputdir"
}

Shortcut_Script(){
	case $1 in
		create)
			if [ -d /opt/bin ] && [ ! -f "/opt/bin/$SCRIPT_NAME_LOWER" ] && [ -f "/jffs/scripts/$SCRIPT_NAME_LOWER" ]; then
				ln -s /jffs/scripts/"$SCRIPT_NAME_LOWER" /opt/bin
				chmod 0755 /opt/bin/"$SCRIPT_NAME_LOWER"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$SCRIPT_NAME_LOWER" ]; then
				rm -f /opt/bin/"$SCRIPT_NAME_LOWER"
			fi
		;;
	esac
}

Process_Upgrade(){
	if [ ! -f "$SCRIPT_STORAGE_DIR/.tableupgraded" ]; then
		{
			echo "ALTER TABLE ntpstats RENAME COLUMN [Frequency] TO [Sys_Jitter2];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Sys_Jitter] TO [Clk_Jitter2];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Clk_Jitter] TO [Clk_Wander2];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Clk_Wander] TO [Frequency2];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Sys_Jitter2] TO [Sys_Jitter];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Clk_Jitter2] TO [Clk_Jitter];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Clk_Wander2] TO [Clk_Wander];"
			echo "ALTER TABLE ntpstats RENAME COLUMN [Frequency2] TO [Frequency];"
		} > /tmp/ntp-stats.sql
		"$SQLITE3_PATH" "$SCRIPT_STORAGE_DIR/ntpdstats.db" < /tmp/ntp-stats.sql >/dev/null 2>&1
		touch "$SCRIPT_STORAGE_DIR/.tableupgraded"
	fi
	if [ ! -f "$SCRIPT_DIR/timeserverd" ]; then
		Update_File timeserverd
	fi
}

PressEnter(){
	while true; do
		printf "Press enter to continue..."
		read -r key
		case "$key" in
			*)
				break
			;;
		esac
	done
	return 0
}

ScriptHeader(){
	clear
	DST_ENABLED="$(nvram get time_zone_dst)"
	if ! Validate_Number "" "$DST_ENABLED" silent; then DST_ENABLED=0; fi
	if [ "$DST_ENABLED" -eq 0 ]; then
		DST_ENABLED="Inactive"
	else
		DST_ENABLED="Active"
	fi
	
	TIMESERVER_NAME_MENU="$(TimeServer check)"
	CONFFILE_MENU=""
	if [ "$TIMESERVER_NAME_MENU" = "ntpd" ]; then
		CONFFILE_MENU="$SCRIPT_STORAGE_DIR/ntp.conf"
	elif [ "$TIMESERVER_NAME_MENU" = "chronyd" ]; then
		CONFFILE_MENU="$SCRIPT_STORAGE_DIR/chrony.conf"
	fi
	
	DST_SETTING="$(nvram get time_zone_dstoff)"
	DST_SETTING="$(echo "$DST_SETTING" | sed 's/M//g')"
	DST_START="$(echo "$DST_SETTING" | cut -f1 -d",")"
	DST_START="Month $(echo "$DST_START" | cut -f1 -d".") Week $(echo "$DST_START" | cut -f2 -d".") Weekday $(echo "$DST_START" | cut -f3 -d"." | cut -f1 -d"/") Hour $(echo "$DST_START" | cut -f3 -d"." | cut -f2 -d"/")"
	DST_END="$(echo "$DST_SETTING" | cut -f2 -d",")"
	DST_END="Month $(echo "$DST_END" | cut -f1 -d".") Week $(echo "$DST_END" | cut -f2 -d".") Weekday $(echo "$DST_END" | cut -f3 -d"." | cut -f1 -d"/") Hour $(echo "$DST_END" | cut -f3 -d"." | cut -f2 -d"/")"
	
	printf "\\n"
	printf "\\e[1m############################################################\\e[0m\\n"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##          _           __  __              _  _          ##\\e[0m\\n"
	printf "\\e[1m##         | |         |  \/  |            | |(_)         ##\\e[0m\\n"
	printf "\\e[1m##   _ __  | |_  _ __  | \  / |  ___  _ __ | | _  _ __    ##\\e[0m\\n"
	printf "\\e[1m##  | '_ \ | __|| '_ \ | |\/| | / _ \| '__|| || || '_ \   ##\\e[0m\\n"
	printf "\\e[1m##  | | | || |_ | |_) || |  | ||  __/| |   | || || | | |  ##\\e[0m\\n"
	printf "\\e[1m##  |_| |_| \__|| .__/ |_|  |_| \___||_|   |_||_||_| |_|  ##\\e[0m\\n"
	printf "\\e[1m##              | |                                       ##\\e[0m\\n"
	printf "\\e[1m##              |_|                                       ##\\e[0m\\n"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##                   %s on %-9s                  ##\\e[0m\\n" "$SCRIPT_VERSION" "$ROUTER_MODEL"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##        https://github.com/jackyaz/ntpMerlin            ##\\e[0m\\n"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##             Time server in use: %-20s   ##\\e[0m\\n" "$TIMESERVER_NAME_MENU"
	printf "\\e[1m##  Config location: %-36s ##\\e[0m\\n" "$CONFFILE_MENU"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##                DST is currently %-8s               ##\\e[0m\\n" "$DST_ENABLED"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##     DST starts on %-33s    ##\\e[0m\\n" "$DST_START"
	printf "\\e[1m##     DST ends on %-33s      ##\\e[0m\\n" "$DST_END"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m############################################################\\e[0m\\n"
	printf "\\n"
}

MainMenu(){
	NTP_REDIRECT_ENABLED=""
	if Auto_NAT check; then
		NTP_REDIRECT_ENABLED="Enabled"
	else
		NTP_REDIRECT_ENABLED="Disabled"
	fi
	TIMESERVER_NAME_MENU="$(TimeServer check)"
	
	printf "1.    Generate updated %s graphs now\\n\\n" "$SCRIPT_NAME"
	printf "2.    Toggle redirect of all NTP traffic to %s\\n      (currently %s)\\n\\n" "$SCRIPT_NAME" "$NTP_REDIRECT_ENABLED"
	printf "3.    Edit %s config\\n\\n" "$SCRIPT_NAME"
	printf "4.    Toggle data output mode\\n      Currently \\e[1m%s\\e[0m values will be used for weekly and monthly charts\\n\\n" "$(OutputDataMode check)"
	printf "5.    Toggle time output mode\\n      Currently \\e[1m%s\\e[0m time values will be used for CSV exports\\n\\n" "$(OutputTimeMode check)"
	printf "s.    Toggle storage location for stats and config\\n      Current location is \\e[1m%s\\e[0m \\n\\n" "$(ScriptStorageLocation check)"
	printf "t.    Switch timeserver between ntpd and chronyd\\n      Currently using \\e[1m%s\\e[0m\\n\\n" "$TIMESERVER_NAME_MENU"
	printf "r.    Restart %s\\n\\n" "$TIMESERVER_NAME_MENU"
	printf "u.    Check for updates\\n"
	printf "uf.   Update %s with latest version (force update)\\n\\n" "$SCRIPT_NAME"
	printf "e.    Exit %s\\n\\n" "$SCRIPT_NAME"
	printf "z.    Uninstall %s\\n" "$SCRIPT_NAME"
	printf "\\n"
	printf "\\e[1m############################################################\\e[0m\\n"
	printf "\\n"
	
	while true; do
		printf "Choose an option:    "
		read -r menu
		case "$menu" in
			1)
				printf "\\n"
				if Check_Lock menu; then
					Menu_GenerateStats
				fi
				PressEnter
				break
			;;
			2)
				printf "\\n"
				Menu_ToggleNTPRedirect
				PressEnter
				break
			;;
			3)
				printf "\\n"
				if Check_Lock menu; then
					Menu_Edit
				fi
				break
			;;
			4)
				printf "\\n"
				Menu_ToggleOutputDataMode
				break
			;;
			5)
				printf "\\n"
				Menu_ToggleOutputTimeMode
				break
			;;
			s)
				printf "\\n"
				Menu_ToggleStorageLocation
				break
			;;
			t)
				printf "\\n"
				if Check_Lock menu; then
					Menu_ToggleTimeServer
				fi
				break
			;;
			r)
				printf "\\n"
				Menu_RestartTimeServer
				PressEnter
				break
			;;
			u)
				printf "\\n"
				if Check_Lock menu; then
					Menu_Update
				fi
				PressEnter
				break
			;;
			uf)
				printf "\\n"
				if Check_Lock menu; then
					Menu_ForceUpdate
				fi
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\\n\\e[1mThanks for using %s!\\e[0m\\n\\n\\n" "$SCRIPT_NAME"
				exit 0
			;;
			z)
				while true; do
					printf "\\n\\e[1mAre you sure you want to uninstall %s? (y/n)\\e[0m\\n" "$SCRIPT_NAME"
					read -r confirm
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*)
							break
						;;
					esac
				done
			;;
			*)
				printf "\\nPlease choose a valid option\\n\\n"
			;;
		esac
	done
	
	ScriptHeader
	MainMenu
}

Check_Requirements(){
	CHECKSFAILED="false"
	
	if [ "$(nvram get jffs2_scripts)" -ne 1 ]; then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output true "Custom JFFS Scripts enabled" "$WARN"
	fi
	
	if [ ! -f /opt/bin/opkg ]; then
		Print_Output true "Entware not detected!" "$ERR"
		CHECKSFAILED="true"
	fi
	
	if ! Firmware_Version_Check install ; then
		Print_Output true "Unsupported firmware version detected" "$ERR"
		Print_Output true "$SCRIPT_NAME requires Merlin 384.15/384.13_4 or Fork 43E5 (or later)" "$ERR"
		CHECKSFAILED="true"
	fi
	
	NTP_Firmware_Check
	
	if [ "$CHECKSFAILED" = "false" ]; then
		Print_Output true "Installing required packages from Entware" "$PASS"
		opkg update
		opkg install sqlite3-cli
		opkg install ntp-utils
		opkg install ntpd
		return 0
	else
		return 1
	fi
}

Menu_Install(){
	Print_Output true "Welcome to $SCRIPT_NAME $SCRIPT_VERSION, a script by JackYaz"
	sleep 1
	
	Print_Output true "Checking your router meets the requirements for $SCRIPT_NAME"
	
	if ! Check_Requirements; then
		Print_Output true "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter
		Clear_Lock
		rm -f "/jffs/scripts/$SCRIPT_NAME_LOWER" 2>/dev/null
		exit 1
	fi
	
	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local
	ScriptStorageLocation load
	Create_Symlinks
	
	Update_File ntp.conf
	Update_File ntpdstats_www.asp
	Update_File shared-jy.tar.gz
	Update_File timeserverd
	
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	TimeServer_Customise
	Get_TimeServer_Stats
	Clear_Lock
}

Menu_Startup(){
	if [ -z "$1" ]; then
		Print_Output true "Missing argument for startup, not starting $SCRIPT_NAME" "$WARN"
		exit 1
	elif [ "$1" != "force" ]; then
		if [ ! -f "$1/entware/bin/opkg" ]; then
			Print_Output true "$1 does not contain Entware, not starting $SCRIPT_NAME" "$WARN"
			exit 1
		else
			Print_Output true "$1 contains Entware, starting $SCRIPT_NAME" "$WARN"
		fi
	fi
	
	NTP_Ready
	
	Check_Lock
	
	if [ "$1" != "force" ]; then
		sleep 7
	fi
	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local
	ScriptStorageLocation load
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	NTP_Firmware_Check
	Shortcut_Script create
	Mount_WebUI
	Clear_Lock
}

Menu_GenerateStats(){
	Get_TimeServer_Stats
	Clear_Lock
}

Menu_ToggleOutputDataMode(){
	if [ "$(OutputDataMode check)" = "raw" ]; then
		OutputDataMode average
	elif [ "$(OutputDataMode check)" = "average" ]; then
		OutputDataMode raw
	fi
}

Menu_ToggleOutputTimeMode(){
	if [ "$(OutputTimeMode check)" = "unix" ]; then
		OutputTimeMode non-unix
	elif [ "$(OutputTimeMode check)" = "non-unix" ]; then
		OutputTimeMode unix
	fi
}

Menu_ToggleTimeServer(){
	if [ "$(TimeServer check)" = "ntpd" ]; then
		TimeServer chronyd
	elif [ "$(TimeServer check)" = "chronyd" ]; then
		TimeServer ntpd
	fi
	Clear_Lock
}

Menu_ToggleStorageLocation(){
	if [ "$(ScriptStorageLocation check)" = "jffs" ]; then
		ScriptStorageLocation usb
		Create_Symlinks
	elif [ "$(ScriptStorageLocation check)" = "usb" ]; then
		ScriptStorageLocation jffs
		Create_Symlinks
	fi
}

Menu_Edit(){
	texteditor=""
	exitmenu="false"
	
	printf "\\n\\e[1mA choice of text editors is available:\\e[0m\\n"
	printf "1.    nano (recommended for beginners)\\n"
	printf "2.    vi\\n"
	printf "\\ne.    Exit to main menu\\n"
	
	while true; do
		printf "\\n\\e[1mChoose an option:\\e[0m    "
		read -r editor
		case "$editor" in
			1)
				texteditor="nano -K"
				break
			;;
			2)
				texteditor="vi"
				break
			;;
			e)
				exitmenu="true"
				break
			;;
			*)
				printf "\\nPlease choose a valid option\\n\\n"
			;;
		esac
	done
	
	if [ "$exitmenu" != "true" ]; then
		TIMESERVER_NAME="$(TimeServer check)"
		CONFFILE=""
		if [ "$TIMESERVER_NAME" = "ntpd" ]; then
			CONFFILE="$SCRIPT_STORAGE_DIR/ntp.conf"
		elif [ "$TIMESERVER_NAME" = "chronyd" ]; then
			CONFFILE="$SCRIPT_STORAGE_DIR/chrony.conf"
		fi
		oldmd5="$(md5sum "$CONFFILE" | awk '{print $1}')"
		$texteditor "$CONFFILE"
		newmd5="$(md5sum "$CONFFILE" | awk '{print $1}')"
		if [ "$oldmd5" != "$newmd5" ]; then
			"/opt/etc/init.d/S77$TIMESERVER_NAME" restart >/dev/null 2>&1
		fi
	fi
	Clear_Lock
}

Menu_ToggleNTPRedirect(){
	if Auto_NAT check; then
		Auto_NAT delete
		NTP_Redirect delete
		printf "\\e[1mNTP Redirect has been disabled\\e[0m\\n\\n"
	else
		Auto_NAT create
		NTP_Redirect create
		printf "\\e[1mNTP Redirect has been enabled\\e[0m\\n\\n"
	fi
}

Menu_RestartTimeServer(){
	TIMESERVER_NAME="$(TimeServer check)"
	Print_Output true "Restarting $TIMESERVER_NAME..." "$PASS"
	"/opt/etc/init.d/S77$TIMESERVER_NAME" restart >/dev/null 2>&1
}

Menu_Update(){
	Update_Version
	Clear_Lock
}

Menu_ForceUpdate(){
	Update_Version force
	Clear_Lock
}

Menu_Uninstall(){
	Print_Output true "Removing $SCRIPT_NAME..." "$PASS"
	Auto_Startup delete 2>/dev/null
	Auto_Cron delete 2>/dev/null
	Auto_ServiceEvent delete 2>/dev/null
	Auto_NAT delete
	NTP_Redirect delete
	
	Get_WebUI_Page "$SCRIPT_DIR/ntpdstats_www.asp"
	if [ -n "$MyPage" ] && [ "$MyPage" != "none" ] && [ -f "/tmp/menuTree.js" ]; then
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		umount /www/require/modules/menuTree.js
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
		rm -rf "{$SCRIPT_WEBPAGE_DIR:?}/$MyPage"
	fi
	rm -f "$SCRIPT_DIR/ntpdstats_www.asp" 2>/dev/null
	rm -rf "$SCRIPT_WEB_DIR" 2>/dev/null
	
	Shortcut_Script delete
	TIMESERVER_NAME="$(TimeServer check)"
	"/opt/etc/init.d/S77$TIMESERVER_NAME" stop >/dev/null 2>&1
	opkg remove --autoremove ntpd
	opkg remove --autoremove ntp-utils
	opkg remove --autoremove chrony
	
	rm -f /opt/etc/init.d/S77ntpd
	rm -f /opt/etc/init.d/S77chronyd
	
	SETTINGSFILE=/jffs/addons/custom_settings.txt
	sed -i '/ntpmerlin_version_local/d' "$SETTINGSFILE"
	sed -i '/ntpmerlin_version_server/d' "$SETTINGSFILE"
	
	printf "\\n\\e[1mDo you want to delete %s configuration file and stats? (y/n)\\e[0m\\n" "$SCRIPT_NAME"
	read -r confirm
	case "$confirm" in
		y|Y)
			rm -rf "$SCRIPT_DIR" 2>/dev/null
			rm -rf "$SCRIPT_STORAGE_DIR" 2>/dev/null
		;;
		*)
			:
		;;
	esac
	
	rm -f "/jffs/scripts/$SCRIPT_NAME_LOWER" 2>/dev/null
	Clear_Lock
	Print_Output true "Uninstall completed" "$PASS"
}

NTP_Ready(){
	if [ "$(nvram get ntp_ready)" -eq 0 ]; then
		Check_Lock
		ntpwaitcount="0"
		while [ "$(nvram get ntp_ready)" -eq 0 ] && [ "$ntpwaitcount" -lt 300 ]; do
			ntpwaitcount="$((ntpwaitcount + 1))"
			if [ "$ntpwaitcount" -eq 60 ]; then
				Print_Output true "Waiting for NTP to sync..." "$WARN"
			fi
			sleep 1
		done
		if [ "$ntpwaitcount" -ge 300 ]; then
			Print_Output true "NTP failed to sync after 5 minutes. Please resolve!" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "NTP synced, $SCRIPT_NAME will now continue" "$PASS"
			Clear_Lock
		fi
	fi
}

### function based on @Adamm00's Skynet USB wait function ###
Entware_Ready(){
	if [ ! -f /opt/bin/opkg ]; then
		Check_Lock
		sleepcount=1
		while [ ! -f /opt/bin/opkg ] && [ "$sleepcount" -le 10 ]; do
			Print_Output true "Entware not found, sleeping for 10s (attempt $sleepcount of 10)" "$ERR"
			sleepcount="$((sleepcount + 1))"
			sleep 10
		done
		if [ ! -f /opt/bin/opkg ]; then
			Print_Output true "Entware not found and is required for $SCRIPT_NAME to run, please resolve" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "Entware found, $SCRIPT_NAME will now continue" "$PASS"
			Clear_Lock
		fi
	fi
}
### ###

if [ -f "/opt/share/$SCRIPT_NAME_LOWER.d/config" ]; then
	SCRIPT_CONF="/opt/share/$SCRIPT_NAME_LOWER.d/config"
	SCRIPT_STORAGE_DIR="/opt/share/$SCRIPT_NAME_LOWER.d"
else
	SCRIPT_CONF="/jffs/addons/$SCRIPT_NAME_LOWER.d/config"
	SCRIPT_STORAGE_DIR="/jffs/addons/$SCRIPT_NAME_LOWER.d"
fi

CSV_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/csv"

if [ -z "$1" ]; then
	NTP_Ready
	Entware_Ready
	if [ ! -f /opt/bin/sqlite3 ]; then
		Print_Output true "Installing required version of sqlite3 from Entware" "$PASS"
		opkg update
		opkg install sqlite3-cli
	fi
	
	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local
	ScriptStorageLocation load
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	Process_Upgrade
	ScriptHeader
	MainMenu
	exit 0
fi

case "$1" in
	install)
		Check_Lock
		Menu_Install
		exit 0
	;;
	startup)
		Menu_Startup "$2"
		exit 0
	;;
	generate)
		NTP_Ready
		Entware_Ready
		Check_Lock
		Menu_GenerateStats
		exit 0
	;;
	outputcsv)
		NTP_Ready
		Entware_Ready
		Check_Lock
		Generate_CSVs
		Clear_Lock
		exit 0
	;;
	service_event)
		if [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME_LOWER" ]; then
			Menu_GenerateStats
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME_LOWER}config" ]; then
			Conf_FromSettings
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME_LOWER}checkupdate" ]; then
			Update_Check
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME_LOWER}doupdate" ]; then
			Update_Version force unattended
			exit 0
		fi
		exit 0
	;;
	ntpredirect)
		Print_Output true "Sleeping for 5s to allow firewall/nat startup to be completed..." "$PASS"
		sleep 5
		Auto_NAT create
		NTP_Redirect create
		exit 0
	;;
	update)
		Update_Version unattended
		exit 0
	;;
	forceupdate)
		Update_Version force unattended
		exit 0
	;;
	setversion)
		Set_Version_Custom_Settings local
		Set_Version_Custom_Settings server "$SCRIPT_VERSION"
		if [ -z "$2" ]; then
			exec "$0"
		fi
		exit 0
	;;
	checkupdate)
		Update_Check
		exit 0
	;;
	uninstall)
		Check_Lock
		Menu_Uninstall
		exit 0
	;;
	develop)
		SCRIPT_BRANCH="develop"
		SCRIPT_REPO="https://raw.githubusercontent.com/jackyaz/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	stable)
		SCRIPT_BRANCH="master"
		SCRIPT_REPO="https://raw.githubusercontent.com/jackyaz/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	*)
		echo "Command not recognised, please try again"
		exit 1
	;;
esac
