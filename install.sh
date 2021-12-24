#!/usr/bin/env bash

stty -echoctl
trap 'exit' INT TERM
trap 'kill 0' EXIT QUIT
trap '__exit_on_error' ERR

FABKIT_DEFAULT_PATH="${HOME}/.fabkit"
FABKIT_DOCKER_IMAGE="everledgerio/fabkit"
FABKIT_LOGFILE=".fabkit.log"
# TODO: Retrieve latest available version from web
FABKIT_VERSION="latest"
ALIASES=("fabkit" "fk")

__error() {
    local input

    if [ -n "$1" ]; then
        input="$1"
        red "[ERROR] $input"
        echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") [ERROR] $input" >>"$FABKIT_LOGFILE"
    else
        local count=0
        while read -r input; do
            if [ $count -eq 0 ]; then
                ((count++)) || true
                echo
            fi
            red "[ERROR] $input"
            echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") [ERROR] $input" >>"$FABKIT_LOGFILE"
        done
    fi
}

__exit_on_error() {
    echo "Check the log file for more details: $(yellow "cat $FABKIT_LOGFILE")"
    kill 0
}

__check_deps() {
    if ! type -p git &>/dev/null; then
        __error "git required but not installed"
        exit 1
    fi
}

__overwrite_line() {
    local pattern=$1
    local text_to_replace=$2
    local file=$3
    local new_text=${text_to_replace//\//\\\/}

    sed -i'.bak' '/'"${pattern}"'/s/.*/'"${new_text}"'/' "${file}"

    mv "${file}.bak" "$HOME" &>/dev/null
}

__setup() {
    local shell="$1"
    local profile="${HOME}/.${shell}rc"
    local cmd=""

    if [ "$shell" = "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    if ! grep -q "^export FABKIT_ROOT=" <"$profile"; then
        cmd+="export FABKIT_ROOT=\"${FABKIT_ROOT}\"\n"
    else
        __overwrite_line "export FABKIT_ROOT" "export FABKIT_ROOT=\"${FABKIT_ROOT}\"" "$profile"
    fi

    for alias in "${ALIASES[@]}"; do
        if ! grep -q "alias ${alias}" <"$profile"; then
            cmd+="alias ${alias}=\"${FABKIT_CMD}\"\n"
        else
            __overwrite_line "alias ${alias}" "alias ${alias}=\"${FABKIT_CMD}\"" "$profile"
        fi
    done

    if [ -n "$cmd" ]; then
        echo -e "\n# Fabkit vars to run commands with ease\n${cmd}" >>"$profile"
    fi

    echo
    green "Fabkit aliases have been added to your default shell!"
    echo
    yellow "!!!!! ATTENTION !!!!!"
    echo "You have one last thing to do. Run the following in your terminal:"
    echo
    echo -e "$(yellow "\tsource $profile")"
    echo

    echo "And then try any of: $(
        for a in "${ALIASES[@]}"; do echo -en "$(cyan "${a} | ")"; done
        tput cub 2
    ) - with something like:"
    echo
    echo -e "$(cyan "\tfabkit network start")"
    echo
}

__install() {
    unset FABKIT_ROOT
    while [[ (-n "$yn" && ! "$yn" =~ ^(Y|y)) || -z "$FABKIT_ROOT" || (-n "$FABKIT_ROOT" && ! -d "$FABKIT_ROOT") ]]; do
        read -rp "Where would you like to install Fabkit? [$(yellow "$FABKIT_DEFAULT_PATH")] " FABKIT_ROOT
        FABKIT_ROOT=${FABKIT_ROOT:-${FABKIT_DEFAULT_PATH}}
        FABKIT_ROOT=${FABKIT_ROOT%/}

        # for security reasons we will create a new directory "fabkit" if the path is not empty and it is not an existing fabkit's root
        if [[ "$FABKIT_ROOT" = "$HOME" || ("$FABKIT_ROOT" != "$HOME" && "$(ls -A "$FABKIT_ROOT" &>/dev/null)" && ! -f ${FABKIT_ROOT}/fabkit) ]]; then
            FABKIT_ROOT+="/fabkit"
        fi

        if [ -d "$FABKIT_ROOT" ]; then
            yellow "!!!!! ATTENTION !!!!!"
            yellow "Directory ${FABKIT_ROOT} already exists and cannot be overwritten"
            read -rp "Do you want to delete this directory in order to proceed with the installation? (y/N) " yn
            case $yn in
            [Yy]*)
                if [ -w "$FABKIT_ROOT" ]; then
                    rm -rf "$FABKIT_ROOT" &>/dev/null
                fi
                mkdir -p "$FABKIT_ROOT" &>/dev/null
                ;;
            *) unset FABKIT_ROOT ;;
            esac
        else
            mkdir -p "$FABKIT_ROOT" &>/dev/null
        fi
    done

    if [ -w "$FABKIT_ROOT" ]; then
        (
            if echo -n "Downloading and installing into $(cyan "${FABKIT_ROOT}")" && (__fetch 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__error >&2); then
                __error "There was an error extracting ${FABKIT_TARBALL} into ${FABKIT_ROOT}"
                exit 1
            fi
        ) &
        __spinner
        echo
    else
        yellow "!!!!! ATTENTION !!!!!"
        yellow "Directory \"${FABKIT_ROOT}\" requires superuser permissions"
        yellow "Be sure you are setting an installation path accessible from your current user (preferably under ${HOME})!"
        exit
    fi
}

__fetch() {
    git clone https://github.com/everledger/fabkit.git ${FABKIT_ROOT}
}

__set_installation_type() {
    FABKIT_RUNNER="${FABKIT_ROOT}/fabkit"
    FABKIT_RUNNER_DOCKER="docker run --rm -it --name fabkit -e \"FABKIT_HOST_ROOT=\$FABKIT_ROOT\" -v /var/run/docker.sock:/var/run/docker.sock -v \"\$FABKIT_ROOT\":/home/fabkit everledgerio/fabkit:$FABKIT_VERSION ./fabkit \"\$@\""

    OS="$(uname)"
    case $OS in
    Linux | FreeBSD | Darwin)
        green "Great! It looks like your system supports Fabric natively, but you can also run it in a docker container if you like."

        while [[ ! "$cmd" =~ (1|2) ]]; do
            echo
            blue "Choose any of these options: "
            echo
            cyan "1) Local installation (recommended)"
            cyan "2) Docker installation"
            read -r cmd
            case $cmd in
            1)
                FABKIT_CMD="${FABKIT_RUNNER}"
                green "Roger. Initiating local install!"
                ;;
            2)
                FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
                green "Roger. Initiating docker install!"
                __install_docker &
                __spinner
                ;;
            *) ;;
            esac
        done
        ;;
    *)
        yellow "It looks like your system does NOT support natively Fabric, but don't worry, we've got you covered!"
        FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
        ;;
    esac
}

__install_docker() {
    FABKIT_DOCKER_IMAGE+=":${FABKIT_VERSION:-latest}"
    echo -en "Downloading the official Fabkit docker image $(cyan ${FABKIT_DOCKER_IMAGE})..."
    if (docker pull "${FABKIT_DOCKER_IMAGE}" 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__error >&2); then
        __error "Error pulling ${FABKIT_DOCKER_IMAGE}"
        exit 1
    fi
    if (docker tag "${FABKIT_DOCKER_IMAGE}" "${FABKIT_DOCKER_IMAGE/$FABKIT_VERSION/latest}" 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__error >&2); then
        __error "Error tagging ${FABKIT_DOCKER_IMAGE} to latest"
        exit 1
    fi
}

__spinner() {
    local LC_CTYPE=C
    local pid=$!
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3

    echo -en "\033[3C→ "
    local i=0
    tput cuf1
    while kill -0 "$pid" 2>/dev/null; do
        tput civis
        local i=$(((i + charwidth) % ${#spin}))
        printf "%s" "${spin:$i:$charwidth}"
        tput cub1
        sleep 0.05
    done

    tput el
    tput cnorm
    if wait "$pid"; then
        echo -e "✅ "
    else
        echo -e "❌ "
        exit 1
    fi
}

purple() {
    echo -e "\033[1;35m${1}\033[0m"
}

red() {
    echo -e "\033[1;31m${1}\033[0m"
}

green() {
    echo -e "\033[1;32m${1}\033[0m"
}

yellow() {
    echo -e "\033[1;33m${1}\033[0m"
}

blue() {
    echo -e "\033[1;34m${1}\033[0m"
}

cyan() {
    echo -e "\033[1;36m${1}\033[0m"
}

purple "
        ╔═╗┌─┐┌┐ ┬┌─ ┬┌┬┐
        ╠╣ ├─┤├┴┐├┴┐ │ │ 
        ╚  ┴ ┴└─┘┴ ┴ ┴ ┴ 
             ■-■-■               
    "
blue "Welcome to the Fabkit's interactive setup 🧰 "
echo
read -n 1 -s -r -p "Press any key to start! (or CTRL-C to exit) "
echo
echo

__check_deps

if git remote -v 2>/dev/null | grep -q "fabkit"; then
    cyan "Looks like you want to run Fabkit from inside its repository path."
    echo
    echo "Setting to $(cyan "${FABKIT_VERSION}") version."
    echo "Going to set - $(cyan "${PWD}") - as your installation path!"
    echo
    FABKIT_ROOT="$PWD"
else
    __install
fi

sleep 1
__set_installation_type

sleep 1
echo
green "Congrats! Fabkit is now installed! 🚀"
echo
sleep 1
cyan "And now the final few touches so you can run fabkit anywhere! 😵‍💫🌎"

case $SHELL in
*bash)
    __setup bash
    ;;
*zsh)
    __setup zsh
    ;;
*fish)
    __setup fish
    ;;
esac

sleep 1
echo "For more information visit: $(cyan "https://github.com/everledger/fabkit/tree/master/docs")"
echo
echo
green "Have fun! 💃🕺"
