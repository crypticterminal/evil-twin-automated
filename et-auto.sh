#!/usr/bin/env bash

# Regular colors.
BLACK='\e[0;30m'        # black
RED='\e[0;31m'          # red
GREEN='\e[0;32m'        # green
YELLOW='\e[0;33m'       # yellow
BLUE='\e[0;34m'         # blue
PURPLE='\e[0;35m'       # purple
CYAN='\e[0;36m'         # cyan
WHITE='\e[0;37m'        # white

# Bold colors.
BOLD_BLACK='\e[1;30m'       # black
BOLD_RED='\e[1;31m'         # red
BOLD_GREEN='\e[1;32m'       # green
BOLD_YELLOW='\e[1;33m'      # yellow
BOLD_BLUE='\e[1;34m'        # blue
BOLD_PURPLE='\e[1;35m'      # purple
BOLD_CYAN='\e[1;36m'        # cyan
BOLD_WHITE='\e[1;37m'       # white

# Default
DEFAULT_FOREGROUND_COLOR='\e[39m'   # Default foreground color.

###########################################
# Get information of the chipset.
# Globals:
#   chipset
# Arguments:
#   None
# Returns:
#   None
###########################################

get_chipset() {
    local bus
    local bus_info
    local device_id
    local driver

    if [ -f /sys/class/net/${interface}/device/modalias ]; then
        bus="$(cut -d ":" -f 1 /sys/class/net/${interface}/device/modalias)"
        if [ "${bus}" = "usb" ]; then
            bus_info="$(cut -d ":" -f 2 /sys/class/net/${interface}/device/modalias | cut -b 1-10 | sed 's/^.//;s/p/:/')"
            chipset="$(lsusb -d "${bus_info}" | head -n1 - | cut -f3- -d ":" | sed 's/^....//;s/ Network Connection//g;s/ Wireless Adapter//g;s/^ //')"

        # Broadcom appears to define all the internal buses so we have to detect them here.
        elif [ "${bus}" = "pci" -o "${bus}" = "pcmcia" ]; then
            if [ -f /sys/class/net/$iface/device/vendor ] && [ -f /sys/class/net/$iface/device/device ]; then
                device_id="$(cat /sys/class/net/${interface}/device/vendor):$(cat /sys/class/net/${interface}/device/device)"
                chipset="$(lspci -d ${device_id} | cut -f3- -d ":" | sed 's/Wireless LAN Controller //g;s/ Network Connection//g;s/ Wireless Adapter//;s/^ //')"
            else
                bus_info="$(printf "${ethtool_output}" | grep bus-info | cut -d ":" -f "3-" | sed 's/^ //')"
                chipset="$(lspci | grep "${bus_info}" | head -n1 - | cut -f3- -d ":" | sed 's/Wireless LAN Controller //g;s/ Network Connection//g;s/ Wireless Adapter//;s/^ //')"
                device_id="$(lspci -nn | grep "${bus_info}" | grep '[[0-9][0-9][0-9][0-9]:[0-9][0-9][0-9][0-9]' -o)"
            fi
        elif [ "${bus}" = "sdio" ]; then
            if [ -f /sys/class/net/$iface/device/vendor ] && [ -f /sys/class/net/$iface/device/device ]; then
                device_id="$(cat /sys/class/net/${interface}/device/vendor):$(cat /sys/class/net/${interface}/device/device)"
            fi
            if [ "${device_id}" = '0x02d0:0x4330' ]; then
                chipset='Broadcom 4330'
            elif [ "${device_id}" = '0x02d0:0x4329' ]; then
                chipset='Broadcom 4329'
            elif [ "${device_id}" = '0x02d0:0x4334' ]; then
                chipset='Broadcom 4334'
            elif [ "${device_id}" = '0x02d0:0xa94c' ]; then
                chipset='Broadcom 43340'
            elif [ "${device_id}" = '0x02d0:0xa94d' ]; then
                chipset='Broadcom 43341'
            elif [ "${device_id}" = '0x02d0:0x4324' ]; then
                chipset='Broadcom 43241'
            elif [ "${device_id}" = '0x02d0:0x4335' ]; then
                chipset='Broadcom 4335/4339'
            elif [ "${device_id}" = '0x02d0:0xa962' ]; then
                chipset='Broadcom 43362'
            elif [ "${device_id}" = '0x02d0:0xa9a6' ]; then
                chipset='Broadcom 43430'
            elif [ "${device_id}" = '0x02d0:0x4345' ]; then
                chipset='Broadcom 43455'
            elif [ "${device_id}" = '0x02d0:0x4354' ]; then
                chipset='Broadcom 4354'
            elif [ "${device_id}" = '0x02d0:0xa887' ]; then
                chipset='Broadcom 43143'
            else
                chipset="unable to detect for sdio ${device_id}"
            fi
        else
            chipset="Not pci, usb, or sdio."
        fi
    elif [ -f /sys/class/net/$iface/device/idVendor ] && [ -f /sys/class/net/$iface/device/idProduct ]; then
        device_id="$(cat /sys/class/net/${interface}/device/idVendor):$(cat /sys/class/net/${interface}/device/idProduct)"
        chipset="$(lsusb | grep -i "${device_id}" | head -n1 - | cut -f3- -d ":" | sed 's/^....//;s/ Network Connection//g;s/ Wireless Adapter//g;s/^ //')"
    elif [ "${driver}" = "mac80211_hwsim" ]; then
        chipset="Software simulator of 802.11 radio(s) for mac80211"
    elif $(printf "${ethtool_output}" | awk '/bus-info/ {print $2}' | grep -q bcma)
    then
        bus="bcma"

        if [ "${driver}" = "brcmsmac" ] || [ "${driver}" = "brcmfmac" ] || [ "${driver}" = "b43" ]; then
            chipset="Broadcom on bcma bus, information limited"
        else
            chipset="Unrecognized driver \"${driver}\" on bcma bus"
        fi
    else
        chipset="non-mac80211 device? (report this!)"
    fi
}

###########################################
# Get WI-FI interfaces.
# Globals:
#   interface_list
# Arguments:
#   None
# Returns:
#   None
###########################################
get_interfaces_list() {
	unset interface_list
	for interface in $(ls -1 /sys/class/net); do
		if [ -f /sys/class/net/${interface}/uevent ]; then
			if $(grep -q DEVTYPE=wlan /sys/class/net/${interface}/uevent)
			then
				interface_list="${interface_list}\n ${interface}"
			fi
		fi
	done
	if [ -x "$(command -v iwconfig 2>&1)" ] && [ -x "$(command -v sort 2>&1)" ]; then
		for interface in $(iwconfig 2> /dev/null | sed 's/^\([a-zA-Z0-9_.]*\) .*/\1/'); do
			interface_list="${interface_list}\n ${interface}"
		done
		interface_list="$(printf "${interface_list}" | sort -bu)"
	fi
}

###########################################
# Check if needed programs are installed.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
###########################################
check_programs() {
    if [ -d /sys/bus/pci ] || [ -d /sys/bus/pci_express ] || [ -d /proc/bus/pci ]; then
        if [ ! -x "$(command -v lspci 2>&1)" ]; then
            echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} Please install ${BOLD_PURPLE}lspci{GREEN} from your distro's package manager${WHITE}."
            echo ""
            exit 1
        fi
    fi
    if [ -d /sys/bus/usb ]; then
        if [ ! -x "$(command -v lsusb 2>&1)" ]; then
            echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} Please install ${BOLD_PURPLE}lsusb${GREEN} from your distro's package manager${WHITE}."
            echo ""
            exit 1
        fi
    fi
}

###########################################
# Get chipsets of the interfaces.
# Globals:
#   chipsets_number
#   interfaces
#   chipsets
#   ethtool_output
# Arguments:
#   None
# Returns:
#   None
###########################################
get_interfaces_chipsets() {
    get_interfaces_list
    chipsets_number=0
    for interface in $(printf "${interface_list}"); do
        unset ethtool_output FROM FIRMWARE STACK MADWIFI MAC80211 BUSADDR chipset EXTENDED PHYDEV ifacet DRIVERt FIELD1 FIELD1t FIELD2 FIELD2t CHIPSETt

        ethtool_output="$(ethtool -i "${interface}" 2>&1)"
        if [ "${ethtool_output}" != "Cannot get driver information: Operation not supported" ]; then
            get_chipset ${interface}
            interfaces["${chipsets_number}"]="${interface}"
            chipsets["${chipsets_number}"]="${chipset}"
        else
            echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} ${BOLD_PURPLE}ethtool${GREEN} failed${WHITE}..."
            echo ""
            echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} Only mac80211 devices on kernel 2.6.33 or higher are officially supported by airmon-ng${WHITE}."
            echo ""
            exit 1
        fi
        chipsets_number=$((chipsets_number+1))
    done
}

###########################################
# Get chipsets of the interfaces.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
###########################################
select_interface() {
    local interfaces_number=`iwconfig 2>&1 | grep 'ESSID' | wc -l`
    local interfaces_monitor_mode=`iwconfig 2>&1 | grep 'Mode:Monitor'`

    echo ""
    echo -e ${WHITE}"[${RED}+${WHITE}]${GREEN} Scanning for wireless devices${WHITE}..."

    if [ "${interfaces_number}" -ge 1 ] && [ "${interfaces_monitor_mode}" = "" ]; then
        get_interfaces_chipsets
        echo -e ${WHITE}"[${RED}+${WHITE}]${GREEN} Found ${BOLD_PURPLE}${chipsets_number}${GREEN} wireless device(s)${WHITE}."
        echo ""

        # Formatting table.
        echo -e "${WHITE}+${YELLOW}----${WHITE}+${YELLOW}----------------------${WHITE}+${YELLOW}---------------------------------------------------------${WHITE}+"
        echo -e "${YELLOW}|${RED} ID ${YELLOW}|${RED} Interfaces           ${YELLOW}|${RED} Chipset                                                 ${YELLOW}|"
        echo -e "${WHITE}+${YELLOW}----${WHITE}+${YELLOW}----------------------${WHITE}+${YELLOW}---------------------------------------------------------${WHITE}+"

        for (( c=0; c<${chipsets_number}; c++)); do
            printf "${YELLOW}|${WHITE} %2d ${YELLOW}|${WHITE} %-20s ${YELLOW}|${WHITE} %-55s ${YELLOW}|\n" $((c+1)) "${interfaces[${c}]}" "${chipsets[${c}]}"
        done

        echo -e "${WHITE}+${YELLOW}----${WHITE}+${YELLOW}----------------------${WHITE}+${YELLOW}---------------------------------------------------------${WHITE}+"

    elif [ "${interfaces_number}" -le 0 ]; then
        echo ""
        echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} Is no wireless device to put into ${PURPLE}monitor mode${WHITE}."
        echo ""
    elif [ "${interfaces_number}" -le 0 ] && [ "${interfaces_monitor_mode}" = "" ]; then
        echo ""
        echo -e ${WHITE}"[${RED}!${WHITE}]${GREEN} Wireless Card is ${RED}not found${WHITE}."
    fi
}


main() {
    local result='main'
    while [ "${result}" == 'main' ];
    do
        result=none

        echo -ne '\033c'
        echo -e ${CYAN}   "    +${YELLOW}------------------------------------------------------------------${CYAN}+"
        echo -e ${YELLOW}   "    |                                                                  |"
        echo -e "     |${RED}    ███████╗████████╗    ${GREEN}█████╗ ██╗   ██╗████████╗ ██████╗ ${PURPLE}██╗   ${YELLOW} |"
        echo -e "     |${RED}    ██╔════╝╚══██╔══╝   ${GREEN}██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗${PURPLE}██║   ${YELLOW} |"
        echo -e "     |${BOLD_RED}    █████╗     ██║${WHITE}█████╗${BOLD_GREEN}███████║██║   ██║   ██║   ██║   ██║${BOLD_PURPLE}██║   ${YELLOW} |"
        echo -e "     |${BOLD_RED}    ██╔══╝     ██║${WHITE}╚════╝${BOLD_GREEN}██╔══██║██║   ██║   ██║   ██║   ██║${BOLD_PURPLE}╚═╝   ${YELLOW} |"
        echo -e "     |${BOLD_RED}    ███████╗   ██║      ${GREEN}██║  ██║╚██████╔╝   ██║   ╚██████╔╝${PURPLE}██╗   ${YELLOW} |"
        echo -e "     |${BOLD_RED}    ╚══════╝   ╚═╝      ${GREEN}╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ${PURPLE}╚═╝   ${YELLOW} |"
        echo -e ${YELLOW}   "    |                                                                  |"
        echo -e ${CYAN}   "    +${YELLOW}------------------------------------------------------------------${CYAN}+${YELLOW}"
        echo -e "                        |${BOLD_RED} Evil${BOLD_YELLOW} Twin${BOLD_PURPLE} Automated${BOLD_GREEN} Attack${YELLOW} |"
        echo -e "                        ${CYAN}+${YELLOW}----------------------------${CYAN}+"

        local user_name=`whoami`
        if [ "${user_name}" != "root" ]; then
            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo -e "${WHITE}     | [${RED}!${WHITE}] You need to launch the script as the root user, run it with  ${WHITE}|"
            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo -e "${WHITE}     | ${RED}                    \$${WHITE}=> sudo ${YELLOW}./${GREEN}et${WHITE}-${GREEN}auto${WHITE}.${GREEN}sh${WHITE}                        |"
            echo -e "${WHITE}     | ${RED}                    \$${WHITE}=> sudo ${BLUE}bash ${GREEN}et${WHITE}-${GREEN}auto${WHITE}.${GREEN}sh${WHITE}                     |"
            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo ""
            echo ""
        else
            check_programs

            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo -e "${WHITE}     | ${YELLOW} ID ${WHITE} |                            ${BOLD_PURPLE}Name${WHITE}                           |"
            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo -e "${WHITE}     | ${RED}[${YELLOW}01${RED}]${WHITE} |${GREEN} Start the attack${WHITE}.                                         |"
            echo -e "${WHITE}     | ${RED}[${YELLOW}02${RED}]${WHITE} |${GREEN} Exit${WHITE}.                                                     |"
            echo -e "${YELLOW}     +${WHITE}------------------------------------------------------------------${YELLOW}+"
            echo ""
            echo -e -n "${WHITE}    ${RED} [${CYAN}!${RED}]${WHITE} Type the${BOLD_RED} ID${WHITE} of your choice: "

            local menu_selection
            read menu_selection
            menu_selection=`expr ${menu_selection} + 0 2> /dev/null`

            case "${menu_selection}" in
                "1")
                    select_interface
                    ;;
                "2")
                    echo ""
                    echo -e "${WHITE}     [${GREEN} ok ${WHITE}]${WHITE} See ${BOLD_YELLOW}you${WHITE} next time!"
                    echo ""
			        exit
			        ;;
			    *)
			        echo ""
			        echo -e "${WHITE}     [${RED}!${WHITE}]${RED} Input${WHITE} is out of range."
			        echo ""
			        sleep 2.0
			        result='main'
			        ;;
			esac
        fi
    done
}
main "$@"
