#!/usr/bin/env bash

trap '__quit' INT TERM

ctrlc_count=0

FABKIT_DEFAULT_PATH="${HOME}/.fabkit"
FABKIT_DOCKER_IMAGE="everledgerio/fabkit"

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

ALIASES=("fabkit" "fk")

__add_aliases() {
    local shell="${1}"
    local profile="${HOME}/.${shell}rc"
    local cmd="\n# Fabkit aliases to run commands with ease\n"
    local to_add=false

    if [ "$shell" = "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    grep '^export FABKIT_ROOT=' ~/.profile ~/.*rc &>/dev/null || echo -e "export FABKIT_ROOT=${FABKIT_ROOT}" >>"$profile"
    for alias in "${ALIASES[@]}"; do
        if [[ ! $(cat $profile | grep "alias ${alias}") ]]; then
            cmd+="alias ${alias}="${FABKIT_ROOT}/fabkit"\n"
            to_add=true
        fi
    done

    if [ "${to_add}" = "true" ]; then
        echo -e "$cmd" >>$profile
        source "$profile" 2>/dev/null
    fi
}

loghead() {
    echo -en "\033[1;35m${1}\033[0m"
}

logerr() {
    echo -en "\033[1;31m${1}\033[0m"
}

logsucc() {
    echo -en "\033[1;32m${1}\033[0m"
}

logwarn() {
    echo -en "\033[1;33m${1}\033[0m"
}

loginfo() {
    echo -en "\033[1;34m${1}\033[0m"
}

logdebu() {
    echo -en "\033[1;36m${1}\033[0m"
}

loghead "
        ╔═╗┌─┐┌┐ ┬┌─ ┬┌┬┐
        ╠╣ ├─┤├┴┐├┴┐ │ │ 
        ╚  ┴ ┴└─┘┴ ┴ ┴ ┴ 
             ■-■-■               
    "
loginfo "Hiya! Welcome to the Hyperledger Fabric Toolkit 🧰 (aka Fabkit) interactive setup"
echo
read -p "Press any key to start! (or CTRL-C to exit) "
echo
loginfo "Which version would you like to install? (press RETURN to get the latest):"
echo
logdebu "1) 0.1.0 (latest)"
logdebu "2) 0.1.0-alpha"
read n
case $n in
*)
    # retrieve latest
    FABKIT_VERSION="0.1.0"
    ;;
esac
logsucc "$FABKIT_VERSION"

FABKIT_DOCKER_IMAGE+=":${FABKIT_VERSION}"
FABKIT_TARBALL="fabkit-${FABKIT_VERSION}.tar.gz"
echo "Downloading $(logdebu $FABKIT_TARBALL) ..."
# curl -L https:/bitbucket.org/everledger/${FABKIT_TARBALL}
read -p "Where would you like to install Fabkit? [$(logwarn ${FABKIT_DEFAULT_PATH})] " FABKIT_ROOT
export FABKIT_ROOT=${FABKIT_ROOT:-${FABKIT_DEFAULT_PATH}}
export FABKIT_RUNNER="${FABKIT_ROOT}/fabkit"
export FABKIT_RUNNER_DOCKER='docker run -it --rm --name fabkit -e "FABKIT_HOST_ROOT=$FABKIT_ROOT" -v /var/run/docker.sock:/var/run/docker.sock -v "$FABKIT_ROOT":/home/fabkit everledgerio/fabkit:latest ./fabkit "$@"'
if [ -w "$FABKIT_ROOT" ]; then
    lodebu "Extracting..."
    # tar -C "$FABKIT_ROOT" -xzvf "${FABKIT_TARBALL}"
    # rm ${FABKIT_TARBALL}
else
    lowarn "!!!!! ATTENTION !!!!!"
    loginfo "Directory \"${FABKIT_ROOT}\" requires superuser permissions"
    loginfo "I am going to close for now. Be sure you are setting an installation path accessible from your current user (preferably under ${HOME}). Cheers!"
    exit
fi
logsucc "Kewl! 👍 Fabkit is now installed. Let me help you with a couple of more things ✨"
echo

OS="$(uname)"
case $OS in
Linux | FreeBSD | Darwin)
    loginfo "Great! It looks like your system supports natively Fabric, but you can also run it a docker container if you prefer!"
    echo
    loginfo "Choose any of these options: "
    echo
    logdebu "1) Local installation (recommended)"
    logdebu "2) Docker installation"

    read n
    case $n in
    1)
        FABKIT_CMD="${FABKIT_RUNNER}"
        logsucc "Roger. Going for local installation!"
        ;;
    2)
        FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
        logsucc "Roger. Going for docker installation!"
        ;;
    esac
    ;;
*)
    logwarn "It looks like your system does NOT support natively Fabric, but do not worry, we got you covered! 😉"
    FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
    ;;
esac

if [ "$FABKIT_CMD" = "$FABKIT_RUNNER_DOCKER" ]; then
    loginfo "Fabkit could run in a docker container everywhere! 😵‍💫🌎 We only need to download the image. Bear with me 😉"
    echo "Downloading docker image $(logdebu ${FABKIT_DOCKER_IMAGE}) ..."
    docker pull "${FABKIT_DOCKER_IMAGE}"
fi

logsucc "Got it!"
echo
logdebu "And now the last few touches to run fabkit anywhere!"
logwarn "Setting up your runners..."

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

logsucc "Fabkit aliases have been added to your default shell! Try now to use any of - $(for a in "${ALIASES[@]}"; do printf %s${a}; done) - with something like:"
echo
logdebu ">>> fabkit network start"
echo
logsucc "Have fun! 💃🏽🕺"
