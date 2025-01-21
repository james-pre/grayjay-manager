#!/usr/bin/env bash
# A script to manage Grayjay installations

# Configuration / Defaults
SCRIPT_VERSION="prototype-1"
FETCH_URL="https://updater.grayjay.app/Apps/Grayjay.Desktop/Grayjay.Desktop-linux-x64.zip"

# Global Variables
VERBOSE=0
LOCAL_INSTALL=0
COMMAND=""
TMP_DIR="/tmp/grayjay-manager"
mkdir -p "$TMP_DIR"
PREFIX=""
installation=""
binary_link=""

# Helpers
print_help() {
	cat <<EOF
Usage: $(basename "$0") [flags] <command>

Flags:
    -w, --verbose   Enable verbose output
    -v, --version   Print the current version and exit
        --local     Perform a local installation in \$HOME/.local
    -h, --help      Print this help message

Commands:
    i, install      Install Grayjay
    rm, remove      Remove Grayjay
    up, update      Update Grayjay
    check           Check that Grayjay is properly installed
    clean           Clean up temporary files
EOF
}

# Clean up temporary files
cleanup() {
	if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR/*"
	fi
}

# Download and unpack Grayjay into a temporary directory.
fetch_gj() {
	pushd "$TMP_DIR" >/dev/null 2>&1

	[[ $VERBOSE -eq 1 ]] && echo "Downloading from $FETCH_URL"
	curl -sLO "$FETCH_URL" || {
		echo "Error: Failed to download from $FETCH_URL"
		cleanup
		exit 1
	}

	ZIP_FILE="$(basename "$FETCH_URL")"
	[[ $VERBOSE -eq 1 ]] && echo "Unzipping $ZIP_FILE"
	unzip -q "$ZIP_FILE" || {
		echo "Error: Failed to unzip $ZIP_FILE"
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
			[[ $VERBOSE -eq 1 ]] && echo "Flattening single directory: $single_dir"
			shopt -s dotglob
			mv "$single_dir"/* .
			rmdir "$single_dir"
			shopt -u dotglob
		fi
	fi

	popd >/dev/null 2>&1
}

# Compare fetched contents in TMP_DIR to the existing install directory.
# Return 0 if differences exist, 1 if no difference.
compare_fetched_to_install() {
	[[ ! -d "$installation" ]] && return 0
	diff -r "$TMP_DIR" "$installation" >/dev/null 2>&1
	if [[ $? -eq 0 ]]; then
		return 1  # no differences
	else
		return 0  # differences exist
	fi
}

# Subcommand Implementations
do_install() {
	fetch_gj

	[[ $VERBOSE -eq 1 ]] && echo "Creating installation directory: $installation"
	mkdir -p "$installation" || {
		echo "Error: Failed to create directory $installation"
		cleanup
		exit 1
	}

	[[ $VERBOSE -eq 1 ]] && echo "Copying files to $installation"
	cp -r "$TMP_DIR"/* "$installation"/ || {
		echo "Error: Failed to copy files to $installation"
		cleanup
		exit 1
	}

	[[ $VERBOSE -eq 1 ]] && echo "Creating symlink: $binary_link -> $installation/Grayjay"
	ln -sf "$installation/Grayjay" "$binary_link" || {
		echo "Error: Failed to create symlink $binary_link"
		cleanup
		exit 1
	}

	cleanup
	[[ $VERBOSE -eq 1 ]] && echo "Installation complete."
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
		[[ $VERBOSE -eq 1 ]] && echo "Removing installation directory: $installation"
		rm -rf "$installation"
	}

	if [[ -L "$binary_link" || -f "$binary_link" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Removing symlink: $binary_link"
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

	[[ $VERBOSE -eq 1 ]] && echo "Updating files in $installation"
	mkdir -p "$installation"
	rsync -a "$TMP_DIR"/ "$installation"/ || {
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
	[[ $VERBOSE -eq 1 ]] && echo "Running cleanup."
	cleanup
	exit 0
}

# Argument Parsing
while [[ $# -gt 0 ]]; do
	case "$1" in
		-w|--verbose)
			VERBOSE=1
			shift
			;;
		-v|--version)
			echo "$SCRIPT_VERSION"
			exit 0
			;;
		--local)
			LOCAL_INSTALL=1
			shift
			;;
		-h|--help)
			print_help
			exit 0
			;;
		i|install|rm|remove|up|update|check|clean)
			if [[ -z "$COMMAND" ]]; then
				COMMAND="$1"
			else
				echo "Error: Multiple commands specified ('$COMMAND' and '$1')."
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

if [[ -z "$COMMAND" ]]; then
	echo "Error: No command provided."
	print_help
	exit 1
fi

# Root vs. Local checks & prefix setup
if [[ $(id -u) -eq 0 ]]; then
	# user is root
	if [[ $LOCAL_INSTALL -eq 1 ]]; then
		echo "Error: --local cannot be used as root."
		cleanup
		exit 1
	fi
	PREFIX=""
else
	# user is not root
	if [[ $LOCAL_INSTALL -eq 0 ]]; then
		echo "Error: You must use --local when not running as root."
		cleanup
		exit 1
	fi
	PREFIX="$HOME/.local"
	mkdir -p "$PREFIX/bin"
fi

installation="$PREFIX/opt/grayjay"
binary_link="$PREFIX/bin/grayjay"
if [[ $LOCAL_INSTALL -eq 0 ]]; then
	binary_link="/usr/local/bin/grayjay"
fi
mkdir -p "$(dirname "$installation")" 2>/dev/null || true

# Dispatch
case "$COMMAND" in
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
		echo "Error: Unknown command '$COMMAND'"
		cleanup
		exit 1
		;;
esac
