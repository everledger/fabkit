#!/usr/bin/env bash

trap __quit SIGINT

ctrlc_count=0

FABKIT_DEFAULT_PATH="${HOME}/.fabkit"
FABKIT_DOCKER_IMAGE="everledgerio/fabkit"
FABKIT_RUNNER="${FABKIT_ROOT}/fabkit"
FABKIT_RUNNER_DOCKER='docker run -it --rm --name fabkit -e "FABKIT_ROOT=/home/fabkit" -e "FABKIT_HOST_ROOT=$FABKIT_ROOT" -v /var/run/docker.sock:/var/run/docker.sock -v "$FABKIT_ROOT":/home/fabkit -v "$FABKIT_ROOT":/root/.fabkit everledgerio/fabkit:latest ./fabkit "$@"'

__quit() {
    ((ctrlc_count++))
    echo
    if [[ $ctrlc_count == 1 ]]; then
        echo "Stop that."
    elif [[ $ctrlc_count == 2 ]]; then
        echo "Once more and I quit."
    else
        echo "That's it.  I quit."
        exit
    fi
}

ALIASES=("fabkit" "fk")

__add_aliases() {
    local shell="${1}"
    local profile="${HOME}/.${shell}rc"
    local cmd="\n# Fabkit aliases to run commands with ease\n"
    local to_add=false

    if [ "$shell" == "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    grep '^export FABKIT_ROOT=' ~/.profile ~/.*rc &>/dev/null || echo -e "export FABKIT_ROOT=${FABKIT_ROOT}" >>"$profile"
    for alias in "${ALIASES[@]}"; do
        if [[ ! $(cat $profile | grep "alias ${alias}") ]]; then
            cmd+="alias ${alias}="${FABKIT_ROOT}/fabkit"\n"
            to_add=true
        fi
    done

    if [ "${to_add}" == "true" ]; then
        echo -e "$cmd" >>$profile
        source "$profile" 2>/dev/null
    fi
}

echo "Hiya! Welcome to the Fabkit's interactive setup"
read -p "Press any key to get started! (or CTRL-C to exit) "
echo "Pick any available version:"
echo
echo "1) 0.1.0 (latest)"
echo "2) 0.1.0-alpha"
read n
case $n in
1) # retrieve latest
    FABKIT_VERSION="0.1.0"
    FABKIT_DOCKER_IMAGE+=":${FABKIT_VERSION}"
    ;;
esac
FABKIT_TARBALL="fabkit-${FABKIT_VERSION}.tar.gz"
# curl -sL https:/bitbucket.org/everledger/${FABKIT_TARBALL}
read -p "Where would you like to install Fabkit? [${FABKIT_DEFAULT_PATH}] " path
path=${path:-${FABKIT_DEFAULT_PATH}}
if [ -w "$path" ]; then
    # tar -C "$path" -xzvf "${FABKIT_TARBALL}"
    echo "Extracting..."
else
    echo "!!!!! ATTENTION !!!!!"
    echo "Directory \"${path}\" requires superuser permissions"
    read -p "Do you wish to continue? [yes/no=default] " yn
    case $yn in
    [Yy]*)
        # sudo tar -C "$path" -xzvf "${FABKIT_TARBALL}"
        echo "Extracting..."
        ;;
    *)
        echo "OK. Roger. Going to stop here. Check the README if you prefer a manual installation! Byebye"
        exit
        ;;
    esac
fi
echo "Kewl! Fabkit is now installed. Let me help you with a couple of more things :)"

OS="$(uname)"
case $OS in
Linux | FreeBSD | Darwin)
    echo "Great! It looks like your system supports natively Fabric, but you can also run it a docker container if you prefer!"
    echo "Choose any of these options: "
    echo
    echo "1) As is"
    echo "2) Pull the docker image and use it instead"
    read n
    case $n in
    1) FABKIT_CMD="${FABKIT_RUNNER}" ;;
    2) FABKIT_CMD="${FABKIT_RUNNER_DOCKER}" ;;
    esac
    ;;
*)
    echo "It looks like your system DOES not support natively Fabric :( but do not worry, we got you covered! :)"
    echo "Fabkit could run in a docker container everywhere! We only need to download one more thing. Bear with me ;)"
    FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
    ;;
esac

if [ "$FABKIT_CMD" == "$FABKIT_RUNNER_DOCKER" ]; then
    echo "Downloading docker image ${FABKIT_DOCKER_IMAGE}..."
    # docker pull "${FABKIT_DOCKER_IMAGE}"
else
    sed -i'.bak' "s|.*FABKIT_HOST_ROOT.*|FABKIT_HOST_ROOT=\"${FABKIT_ROOT}\"|" ${FABKIT_ROOT}/.env && rm ${FABKIT_ROOT}/.env.bak
fi

echo "Got it!"
echo
echo "And now the last few touches to run fabkit anywhere!"

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

echo "Fabkit aliases have been added to your default shell! Try now to use any of - $(for a in "${ALIASES[@]}"; do printf "%s$a "; done) - with something like:"
echo "fabkit network start"
echo
echo "Have fun!"
