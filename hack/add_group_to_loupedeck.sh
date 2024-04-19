#!/usr/bin/env bash

LOUPEDECK_VENDOR_ID="2ec2"
LOUPEDECK_PRODUCT_ID="0004"

UDEV_PATH="/etc/udev/rules.d"
UDEV_FILE="99-loupedeck.llc.rules"
UDEV_RULE_TMPL='KERNEL=="ttyACM[0-9]*", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="%s", ATTRS{idProduct}=="%s", GROUP="%s", MODE="%s"'

sudo_warn() {
	local cmd_name="${1}"

	printf -- "\n\nThis script needs to escallate permissions in order to perform the following command:\n\t'%s'\n\n" \
		"${cmd_name}"
	printf -- "Depending on whether or not you've already used sudo recently (in this script or at the prior) and\n"
	printf -- "your sudo password policy, you may be prompted for a sudo password on the next line.\n\n"
}

check_command() {
	local command_name="${1}"

	if command -v "${command_name}" &>/dev/null; then
		return 0
	fi
	printf -- "%s command does not exist, please install before continuing...\n" "${command_name}"
	return 1
}

check_commands() {
	if ! check_command lsusb; then
		return 1
	fi
	if ! check_command grep; then
		return 1
	fi
	if ! check_command sudo; then
		return 1
	fi
	if ! check_command groupadd; then
		return 1
	fi
	if ! check_command awk; then
		return 1
	fi
	if ! check_command groups; then
		return 1
	fi

	return 0
}

find_loupedeck() {
	local lsusb_output

	if ! lsusb_output="$(lsusb -v 2>/dev/null)"; then
		printf -- "was not able to execute lsusb successfully, look for errors when running 'lsusb -v' and resolve\n"
		return 1
	fi

	if ! grep -qF "${LOUPEDECK_VENDOR_ID}" <<<"${lsusb_output}"; then
		printf -- "was not able to find loupedeck USB vendor ID '%s' attached to system\n\n\n" "${LOUPEDECK_VENDOR_ID}"

		if ! grep -iF "loupedeck" <<<"${lsusb_output}"; then
			printf -- "wasn't even able to find a mention of 'loupedeck' in lsusb output, this likely means that\n"
			printf -- "you haven't connected the device to the system or something else is wrong with device\n"
			printf -- "recognition at a system level.\n"

			return 2
		else
			printf -- "was able to find another loupedeck device, it is possible that their device ID may have\n"
			printf -- "shifted. Please report an issue to the project along with the output of 'lsusb -v'\n"

			return 3
		fi
	fi

	if ! grep -qF "${LOUPEDECK_PRODUCT_ID}" <<<"${lsusb_output}"; then
		printf -- "was not able to find Loupedeck Live USB product ID '%s' attached to system\n" \
			"${LOUPEDECK_PRODUCT_ID}"
		printf -- "if you're sure that you have one connected to the system, please report an issue to the project\n"
		printf -- "along with the output of 'lsusb -v'\n"
	fi

	return 0
}

prompt_yes_no() {
	local prompt_text

	prompt_text="${1}"

	read -p "${prompt_text} (y/n)? " choice
	case "$choice" in 
		y|Y|yes|Yes|YES ) return 0;;
		* ) return 1;;
	esac

	return 1
}

prompt_input() {
	local prompt_text

	prompt_text="${1}"

	read -p "${prompt_text}: " user_input

	if [[ -z "${user_input}" ]]; then
		return 1
	fi

	return 0
}

create_group() {
	local user_input

	if prompt_input "Enter name for group (default: ${DEFAULT_GRP_NAME})"; then
		user_group="${user_input}"
	else
		printf -- "\nNo input given, using default '%s'\n" "${DEFAULT_GRP_NAME}"
		user_group="${DEFAULT_GRP_NAME}"
	fi

	sudo_warn "groupadd ${user_group}"
	sudo groupadd "${user_group}" || return 1

	return 0
}

prompt_user_for_group() {
	local DEFAULT_GRP_NAME="llc" user_input

	if prompt_yes_no "Create new group for user?"; then
		create_group || return 1
	else
		if prompt_input "Enter group name of existing group (default: ${DEFAULT_GRP_NAME})"; then
			user_group="${user_input}"
		else
			printf -- "\nNo input given, using default '%s'\n" "${DEFAULT_GRP_NAME}"
			user_group="${DEFAULT_GRP_NAME}"
		fi
	fi

	if ! group_num="$(awk -F':' -v grp_name="${user_group}" '$0 ~ grp_name {print $3}' /etc/group)"; then
		printf -- "Could not search for group ID for group name %s!\n" "${user_group}"
		return 3
	fi

	if [[ -z "${group_num}" || ! "${group_num}" =~ ^[0-9]+$ ]]; then
		printf -- "Group number found '%s' was either blank or not a number!\n" "${group_num}"
		return 4
	fi

	return 0
}

prompt_user_for_mode() {
	local DEFAULT_MODE="0660" user_input


	if prompt_input "Enter mode for device (default: ${DEFAULT_MODE})"; then
		mode_num="${user_input}"
	else
		printf -- "\nNo input given, using default '%s'\n" "${DEFAULT_MODE}"
		mode_num="${DEFAULT_MODE}"
	fi

	if [[ -z "${mode_num}" || ! "${mode_num}" =~ ^[0-7][0-7][0-7][0-7]$ ]]; then
		printf -- "Mode number found '%s' was either blank or not a valid mode number!\n" "${mode_num}"
		return 1
	fi

	return 0
}

add_udev_rule() {
	local udev_input udev_file="${UDEV_PATH}/${UDEV_FILE}"

	if [[ ! -d "${UDEV_PATH}" ]]; then
		printf -- "UDEV path '%s' does not appear to exist, please create or check system.\n" "${UDEV_PATH}"
		return 1
	fi

	if [[ -e "${udev_file}" ]]; then
		printf -- "UDEV rules file %s appears to already exist, if you're sure you want to proceed,\n" "${udev_file}"
		printf -- "please remove the file first. For now, aborting\n"
		return 2
	fi

	udev_input="$(printf -- "${UDEV_RULE_TMPL}" "${LOUPEDECK_VENDOR_ID}" "${LOUPEDECK_PRODUCT_ID}" "${user_group}" "${mode_num}")"

	printf -- "About to write the following udev rule:\n"
	printf -- "\t%s\n\n" "${udev_input}"

	if ! prompt_yes_no "Continue?"; then
		printf -- "Aborting\n"
		return 3
	fi

	sudo_warn "echo '${udev_input}' | sudo tee ${udev_file}"

	echo "${udev_input}" | sudo tee -a "${udev_file}" >/dev/null || return 4

	printf -- "Reloading udev rules\n"

	sudo_warn "udevadm control --reload-rules && udevadm trigger"

	udevadm control --reload-rules && udevadm trigger

	return 0
}

check_user_is_in_group() {
	local groups_out

	if ! groups_out="$(groups)"; then
		printf -- "Could not execute groups command to check if user was in the '%s' group.\n" "${user_group}"
		return 1
	fi

	if ! grep -qF "${user_group}" <<<"${groups_out}"; then
		printf -- "User %s does not appear to be in group %s.\n" "${USER}" "${user_group}"
		printf -- "At the end of this process you will probably need to run the following command and restart\n"
		printf -- "your user session:\n"
		printf -- "\tsudo usermod -G %s %s\n\n" "${user_group}" "${USER}"
	fi
}

main() {
	local usb_group usb_mode group_num mode_num user_group

	check_commands || exit $?
	find_loupedeck || exit $?
	printf -- "Found Loupedeck Product and Device!\n"

	prompt_user_for_group || exit $?
	prompt_user_for_mode || exit $?

	add_udev_rule || exit $?

	check_user_is_in_group
}

main "${@}"
