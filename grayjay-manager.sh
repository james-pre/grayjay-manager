#!/usr/bin/env bash

# A script to manage Grayjay installations

# Configuration / Defaults
version="prototype-1"
zip_url="https://updater.grayjay.app/Apps/Grayjay.Desktop/Grayjay.Desktop-linux-x64.zip"

uid=$(id -u)

# Global Variables
verbose=false
is_local=false
command=""
tmp_dir="/tmp/grayjay-manager"
mkdir -p "$tmp_dir"

if [[ $uid -eq 0 ]]; then
	installation="/opt/grayjay"
	binaries="/usr/local/bin"
else
	installation="$HOME/.local/opt/grayjay"
	binaries="$HOME/.local/bin"
fi
binary_link="$binaries/grayjay"

print_help() {
	cat <<EOF
Usage: $(basename "$0") [flags] <command>

Flags:
    -w, --verbose   Enable verbose output
    -v, --version   Print the current version and exit
        --local     Perform a local installation in ~/.local
    -h, --help      Print this help message

Commands:
    i, install      Install Grayjay
    rm, remove      Remove Grayjay
    up, update      Update Grayjay
    check           Check that Grayjay is properly installed
    clean           Clean up temporary files
EOF
}

# Credit: Dave Dopson, https://stackoverflow.com/a/246128/17637456
script_directory=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Clean up temporary files
cleanup() {
	if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
		rm -rf "$tmp_dir/*"
	fi
}

# Download and unpack Grayjay into a temporary directory.
fetch_gj() {
	pushd "$tmp_dir" >/dev/null 2>&1

	$verbose && echo "Downloading from $zip_url"
	curl -sLO "$zip_url" || {
		echo "Error: Failed to download from $zip_url"
		cleanup
		exit 1
	}

	local zip_file="$(basename "$zip_url")"
	$verbose && echo "Unzipping $zip_file"
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

# Subcommand Implementations
do_install() {
	fetch_gj

	$verbose && echo "Creating installation directory: $installation"
	mkdir -p "$installation" || {
		echo "Error: Failed to create directory $installation"
		cleanup
		exit 1
	}

	$verbose && echo "Copying files to $installation"
	cp -r "$tmp_dir"/* "$installation"/ || {
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
		$verbose && echo "Removing installation directory: $installation"
		rm -rf "$installation"
	}

	if [[ -L "$binary_link" || -f "$binary_link" ]]; then
		$verbose && echo "Removing symlink: $binary_link"
		rm -f "$binary_link"
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

do_check() {
	if [[ ! -d "$installation" ]]; then
		echo "Missing installation: $installation"
		exit 1
	fi

	echo "Found Grayjay: $installation"

	if [[ ! -L "$binary_link" ]]; then
		echo "Missing link: $binary_link"
		exit 1
	fi

	echo "Found link: $binary_link"

	local target="$(readlink "$binary_link")"

	if [[ "$target" != "$installation/Grayjay" ]]; then
		echo "Invalid link target: $target"
		exit 1;
	fi

	echo "Link points to binary: $target"

	echo "Grayjay is properly installed."

}

do_clean() {
	$verbose && echo "Running cleanup."
	cleanup
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
		--local)
			is_local=true
			shift
			;;
		-h|--help)
			print_help
			exit 0
			;;
		i|install|rm|remove|up|update|check|clean)
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

if [[ $uid -eq 0 && $is_local = true ]]; then
	echo "Error: --local cannot be used as root."
	exit 1
fi

if [[ $uid -ne 0 && $is_local = false ]]; then
	echo "Error: You must use --local when not running as root."
	exit 1
fi

mkdir -p "$(dirname "$installation")" 2>/dev/null || true

# Dispatch
case "$command" in
	i|install)
		do_install
		;;
	rm|remove)
		do_remove
		;;
	up|update)
		do_update
		;;
	check)
		do_check
		;;
	clean)
		do_clean
		;;
	*)
		echo "Error: Unknown command '$command'"
		cleanup
		exit 1
		;;
esac
