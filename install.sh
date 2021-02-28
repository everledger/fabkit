#!/usr/bin/env bash

trap '__quit' INT TERM

ctrlc_count=0

FABKIT_DEFAULT_PATH="${HOME}/.fabkit"
FABKIT_DOCKER_IMAGE="everledgerio/fabkit"
ALIASES=("fabkit" "fk")
export FABKIT_RUNNER="${FABKIT_ROOT}/fabkit"
export FABKIT_RUNNER_DOCKER='docker run -it --rm --name fabkit -e "FABKIT_HOST_ROOT=$FABKIT_ROOT" -v /var/run/docker.sock:/var/run/docker.sock -v "$FABKIT_ROOT":/home/fabkit everledgerio/fabkit:latest ./fabkit "$@"'

__quit() {
    ((ctrlc_count++))
    echo
    if [[ $ctrlc_count == 1 ]]; then
        logwarn "Do you really want to quit?"
    else
        echo "Ok byyye"
        exit
    fi
}

__add_aliases() {
    local shell="$1"
    local profile="${HOME}/.${shell}rc"
    local cmd="\n# Fabkit aliases to run commands with ease\n"
    local to_add=false

    if [ "$shell" = "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    grep '^export FABKIT_ROOT=' ~/.profile ~/.*rc &>/dev/null || echo -e "export FABKIT_ROOT=${FABKIT_ROOT}" >>"$profile"
    for alias in "${ALIASES[@]}"; do
        if grep <"$profile" -q "alias ${alias}"; then
            cmd+="alias ${alias}="${FABKIT_ROOT}/fabkit"\n"
            to_add=true
        fi
    done

    if [ "$to_add" = "true" ]; then
        echo -e "$cmd" >>"$profile"
        # shellcheck disable=SC1090
        source "$profile" 2>/dev/null
    fi
}

__download_and_extract() {
    # TODO: Add spinners and beautify direct installation
    loginfo "Which version would you like to install? (press RETURN to get the latest):"
    echo
    logdebu "1) 0.1.0"
    read -r n
    case $n in
    *)
        # retrieve latest
        FABKIT_VERSION="0.1.0"
        ;;
    esac
    logsucc "$FABKIT_VERSION"

    FABKIT_TARBALL="fabkit-${FABKIT_VERSION}.tar.gz"
    echo "Downloading $(logdebu $FABKIT_TARBALL) ..."
    # curl -L https:/bitbucket.org/everledger/${FABKIT_TARBALL}
    read -rp "Where would you like to install Fabkit? [$(logwarn "$FABKIT_DEFAULT_PATH")] " FABKIT_ROOT

    export FABKIT_ROOT=${FABKIT_ROOT:-${FABKIT_DEFAULT_PATH}}

    if [ -w "$FABKIT_ROOT" ]; then
        lodebu "Extracting..."
        # tar -C "$FABKIT_ROOT" -xzvf "${FABKIT_TARBALL}"
        # rm ${FABKIT_TARBALL}
    else
        lowarn "!!!!! ATTENTION !!!!!"
        loginfo "Directory \"${FABKIT_ROOT}\" requires superuser permissions"
        loginfo "Be sure you are setting an installation path accessible from your current user (preferably under ${HOME})!"
        exit
    fi
}

__set_installation_type() {
    OS="$(uname)"
    case $OS in
    Linux | FreeBSD | Darwin)
        loginfo "Great! It looks like your system supports Fabric natively, but you can also run it a docker container."
        echo
        loginfo "Choose any of these options: "
        echo
        logdebu "1) Local installation (recommended)"
        logdebu "2) Docker installation"

        read -r n
        case $n in
        1)
            FABKIT_CMD="${FABKIT_RUNNER}"
            logsucc "Roger. Initiating local install!"
            ;;
        2)
            FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
            logsucc "Roger. Initiating docker install!"
            __install_docker
            ;;
        esac
        ;;
    *)
        logwarn "It looks like your system does NOT support natively Fabric, but don't worry, we've got you covered! 😉"
        FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
        ;;
    esac
}

__install_docker() {
    FABKIT_DOCKER_IMAGE+=":${FABKIT_VERSION}"
    (echo -ne "Downloading the official Fabkit docker image $(logdebu ${FABKIT_DOCKER_IMAGE}) ..." && docker pull "${FABKIT_DOCKER_IMAGE}") &
    __spinner
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

loghead() {
    echo -e "\033[1;35m${1}\033[0m"
}

logerr() {
    echo -e "\033[1;31m${1}\033[0m"
}

logsucc() {
    echo -e "\033[1;32m${1}\033[0m"
}

logwarn() {
    echo -e "\033[1;33m${1}\033[0m"
}

loginfo() {
    echo -e "\033[1;34m${1}\033[0m"
}

logdebu() {
    echo -e "\033[1;36m${1}\033[0m"
}

loghead "
        ╔═╗┌─┐┌┐ ┬┌─ ┬┌┬┐
        ╠╣ ├─┤├┴┐├┴┐ │ │ 
        ╚  ┴ ┴└─┘┴ ┴ ┴ ┴ 
             ■-■-■               
    "
loginfo "Welcome to the Fabkit's interactive setup 🧰"
echo
read -rp "Press any key to start! (or CTRL-C to exit) "
echo

if [[ $(basename $PWD) -eq "fabkit" ]]; then
    FABKIT_VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)
    logdebu "Looks you've cloned the repo. Installing ${FABKIT_VERSION}..."
    echo
    sleep 1
    FABKIT_ROOT=$PWD
else
    __download_and_extract
fi

__set_installation_type

logsucc "Fabkit is now installed 🚀"
echo
logdebu "And now the final few touches so you can run fabkit anywhere!"
echo
sleep 1

case $SHELL in
*bash)
    __add_aliases bash "$FABKIT_CMD"
    ;;
*zsh)
    __add_aliases zsh "$FABKIT_CMD"
    ;;
*fish)
    __add_aliases fish "$FABKIT_CMD"
    ;;
esac

echo
logsucc "Fabkit aliases have been added to your default shell! Try any of: $(
    for a in "${ALIASES[@]}"; do printf %s"${a}, "; done
    tput cub 2
) - with something like:"
logdebu ">>> fabkit network start"
echo

logdebu "For more information visit: https://bitbucket.org/everledger/fabkit/src/master/docs/"
echo
sleep 1
logsucc "Have fun! 🕺"
