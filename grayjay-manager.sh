#!/usr/bin/env bash

# A script to manage Grayjay installations

# Configuration / Defaults
version="prototype-1"
zip_url="https://updater.grayjay.app/Apps/Grayjay.Desktop/Grayjay.Desktop-linux-x64.zip"

uid=$(id -u)

# Global Variables
verbose=false
is_system=false
command=""
tmp_dir="/tmp/grayjay-manager"
mkdir -p "$tmp_dir"

print_help() {
	cat <<EOF
Usage: $(basename "$0") [flags] <command>

Flags:
    -w, --verbose   Enable verbose output
    -v, --version   Print the current version and exit
        --system    System wide installation
    -h, --help      Print this help message

Commands:
    install    Install Grayjay
    remove     Remove Grayjay
    update     Update Grayjay
    check      Check that Grayjay is properly installed
    clean      Clean up temporary files
EOF
}

# Credit: Dave Dopson, https://stackoverflow.com/a/246128/17637456
script_directory=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Clean up temporary files
cleanup() {
	${1:-$verbose} && echo "Running cleanup."
	if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
		rm -rf "$tmp_dir"/*
	fi
}

# Download and unpack Grayjay into a temporary directory.
fetch_gj() {
	pushd "$tmp_dir" >/dev/null 2>&1

	echo "Downloading: $zip_url"
	curl -sLO "$zip_url" || {
		echo "Error: Failed to download from $zip_url"
		cleanup
		exit 1
	}

	local zip_file="$(basename "$zip_url")"
	echo "Unzipping: $zip_file"
	unzip -q "$zip_file" || {
		echo "Error: Failed to unzip $zip_file"
		cleanup
		exit 1
	}

	# If there's exactly one top-level directory, flatten it
	local top_level_count
	top_level_count=$(find . -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
	if [[ $top_level_count -eq 1 ]]; then
		local single_dir
		single_dir=$(find . -mindepth 1 -maxdepth 1 -type d | head -n 1)
		if [[ -n "$single_dir" && "$single_dir" != "." ]]; then
			$verbose && echo "Flattening single directory: $single_dir"
			shopt -s dotglob
			mv "$single_dir"/* .
			rmdir "$single_dir"
			shopt -u dotglob
		fi
	fi

	popd >/dev/null 2>&1
}

# Compare fetched contents in tmp_dir to the existing install directory.
# Return 0 if differences exist, 1 if no difference.
compare_fetched_to_install() {
	[[ ! -d "$installation" ]] && return 0
	diff -r "$tmp_dir" "$installation" >/dev/null 2>&1
	if [[ $? -eq 0 ]]; then
		return 1  # no differences
	else
		return 0  # differences exist
	fi
}

check_install() {
	local output=${1:-false}

	$output && echo "Checking Grayjay installation."

	if [[ ! -d "$installation" ]]; then
		$output && echo "Missing installation: $installation"
		return 1
	fi

	$output && echo "Found Grayjay: $installation"

	if [[ ! -L "$binary_link" ]]; then
		$output && echo "Missing link: $binary_link"
		return 1
	fi

	$output && echo "Found link: $binary_link"

	local target="$(readlink "$binary_link")"

	if [[ "$target" != "$installation/Grayjay" ]]; then
		$output && echo "Invalid link target: $target"
		return 1;
	fi

	$output && echo "Link points to binary: $target"


	if [[ ! -f "$desktop" ]]; then
		$output && echo "Missing application shortcut: $desktop"
		return 1
	fi

	$output && echo "Found application shortcut: $desktop"

	$output && echo "Grayjay is properly installed."

	return 0;
}

do_install() {
	check_install $verbose
	if [[ $? -eq 0 ]]; then
		echo "Grayjay is already installed."
		cleanup
		exit 0
	fi

	fetch_gj

	$verbose && echo "Creating installation directory: $installation"
	mkdir -p "$installation" || {
		echo "Error: Failed to create directory $installation"
		cleanup
		exit 1
	}

	$verbose && echo "Copying files to $installation"
	find "$tmp_dir" -mindepth 1 \( ! -name "$(basename "$zip_url")" \) -exec cp -r {} "$installation/" \; || {
		echo "Error: Failed to copy files to $installation"
		cleanup
		exit 1
	}

	$verbose && echo "Creating symlink: $binary_link -> $installation/Grayjay"
	ln -sf "$installation/Grayjay" "$binary_link" || {
		echo "Error: Failed to create symlink $binary_link"
		cleanup
		exit 1
	}

	$verbose && echo "Creating application shortcut: $desktop"
	echo "$desktop_file_content" > "$desktop" || {
		echo "Error: Failed to create application shortcut"
		cleanup
		exit 1
	}

	cleanup
	$verbose && echo "Installation complete."
	exit 0
}

do_remove() {
	echo "Are you sure you want to remove Grayjay from $installation? [y/N]"
	read -r confirm
	case "$confirm" in
		y|Y|yes|YES)
			;;
		*)
			echo "Aborted."
			cleanup
			exit 0
			;;
	esac

	[[ -d "$installation" ]] && {
		$verbose && echo "Removing: $installation"
		rm -rf "$installation"
	}

	if [[ -L "$binary_link" || -f "$binary_link" ]]; then
		$verbose && echo "Removing: $binary_link"
		rm -f "$binary_link"
	fi

	if [[ -f "$desktop" ]]; then
		$verbose && echo "Removing: $desktop"
		rm -f "$desktop"
	fi

	cleanup
	exit 0
}

do_update() {
	fetch_gj
	compare_fetched_to_install
	if [[ $? -eq 1 ]]; then
		echo "Grayjay is already up to date."
		cleanup
		exit 0
	fi

	$verbose && echo "Updating files in $installation"
	mkdir -p "$installation"
	rsync -a "$tmp_dir"/ "$installation"/ || {
		echo "Error: Failed to sync updated files to $installation"
		cleanup
		exit 1
	}

	cleanup
	echo "Grayjay updated successfully."
	exit 0
}

# Argument Parsing
while [[ $# -gt 0 ]]; do
	case "$1" in
		-w|--verbose)
			verbose=true
			shift
			;;
		-v|--version)
			echo "$version"
			exit 0
			;;
		--system)
			is_system=true
			shift
			;;
		-h|--help)
			print_help
			exit 0
			;;
		install|remove|update|check|clean)
			if [[ -z "$command" ]]; then
				command="$1"
			else
				echo "Error: Multiple commands specified ('$command' and '$1')."
				cleanup
				exit 1
			fi
			shift
			;;
		*)
			echo "Error: Unknown argument '$1'"
			print_help
			cleanup
			exit 1
			;;
	esac
done

if [[ -z "$command" ]]; then
	echo "Error: No command provided."
	print_help
	exit 1
fi


if [[ $uid -ne 0 && $is_system = true ]]; then
	echo "Error: You must root to use --system"
	exit 1
fi

if $is_system; then
	installation="/opt/grayjay"
	binaries="/usr/local/bin"
	applications="/usr/share/applications"
else
	installation="$HOME/.local/opt/grayjay"
	binaries="$HOME/.local/bin"
	applications="$HOME/.local/share/applications"
fi
binary_link="$binaries/grayjay"
desktop="$applications/grayjay.desktop"

desktop_file_content="[Desktop Entry]
Name=Grayjay
Exec=$installation/Grayjay
Path=$installation
Icon=$installation/grayjay.png
Type=Application
Categories=Utility;
" 


mkdir -p "$(dirname "$installation")" 2>/dev/null || true

# Dispatch
case "$command" in
	install)
		do_install
		;;
	remove)
		do_remove
		;;
	update)
		do_update
		;;
	check)
		check_install true
		exit $?
		;;
	clean)
		cleanup true
		;;
	*)
		echo "Error: Unknown command '$command'"
		cleanup
		exit 1
		;;
esac
