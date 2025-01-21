
IS_ROOT=$(id -u) -eq 1

prefix="$( [[ $IS_ROOT -eq 1 ]] && echo "/usr/local/bin" || echo "$HOME/.local/bin" )"

echo "Installing grayjay-manager to $prefix"

script_path="$prefix/grayjay-manager.sh"

if [[ -f "$script_path" ]]; then
	echo "This will overwrite an existing installation of the script."
fi

# prompt to process y/N with enter

# TODO: Finish implementing



