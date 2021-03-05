#!/usr/bin/env bash

stty -echoctl
trap '__quit' INT TERM

CTRLC_COUNT=0
FABKIT_DEFAULT_PATH="${HOME}/.fabkit"
FABKIT_DOCKER_IMAGE="everledgerio/fabkit"
ALIASES=("fabkit" "fk")

__quit() {
    ((CTRLC_COUNT++))
    echo
    if [[ $CTRLC_COUNT == 1 ]]; then
        yellow "Do you really want to quit?"
    else
        echo "Ok byyye"
        exit
    fi
}

__error() {
    red "$1"
    exit 1
}

__escape_slashes() {
    sed 's/\//\\\//g'
}

__overwrite_line() {
    local pattern=$1
    local text_to_replace=$2
    local file=$3
    local new_text=$(echo ${text_to_replace//\//\\\/})

    sed -i'.bak' '/'"${pattern}"'/s/.*/'"${new_text}"'/' "${file}"

    mv "${file}.bak" ~/.
}

__setup() {
    local shell="$1"
    local profile="${HOME}/.${shell}rc"
    local cmd=""

    if [ "$shell" = "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    if [[ ! $(grep "^export FABKIT_ROOT=" "$profile") ]]; then
        cmd+="export FABKIT_ROOT=\"${FABKIT_ROOT}\"\n"
    else
        __overwrite_line "export FABKIT_ROOT" "export FABKIT_ROOT=\"${FABKIT_ROOT}\"" ${profile}
    fi

    for alias in "${ALIASES[@]}"; do
        if ! grep -q "alias ${alias}" <"$profile"; then
            cmd+="alias ${alias}=${FABKIT_CMD}\n"
        else
            __overwrite_line "alias ${alias}" "alias ${alias}=${FABKIT_CMD}" ${profile}
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

__download_and_extract() {
    # TODO: Add spinners and beautify direct installation
    blue "Which version would you like to install? (press RETURN to get the latest):"
    echo
    cyan "1) 0.1.0-rc1"
    read -r n
    case $n in
    *)
        # retrieve latest
        FABKIT_VERSION="0.1.0-rc1"
        ;;
    esac
    green "$FABKIT_VERSION"

    FABKIT_TARBALL="fabkit-${FABKIT_VERSION}.tar.gz"
    echo "Downloading $(cyan $FABKIT_TARBALL)"
    # curl -L https:/bitbucket.org/everledger/${FABKIT_TARBALL} & __spinner
    read -rp "Where would you like to install Fabkit? [$(yellow "$FABKIT_DEFAULT_PATH")] " FABKIT_ROOT

    export FABKIT_ROOT=${FABKIT_ROOT:-${FABKIT_DEFAULT_PATH}}
    while [[ ! "$yn" =~ ^Yy && -d "$FABKIT_ROOT" ]]; do
        if [ -d "$FABKIT_ROOT" ]; then
            yellow "!!!!! ATTENTION !!!!!"
            yellow "Directory ${FABKIT_ROOT} already exists and cannot be overwritten"
            read -rp "Do you want to delete this directory in order to proceed with the installation? [yes/no=default] " yn
            case $yn in
            [Yy]*) if [ -w "$FABKIT_ROOT" ]; then rm -rf "$FABKIT_ROOT"; fi ;;
            *) ;;
            esac
        fi
    done
    mkdir -p "$FABKIT_ROOT" &>/dev/null

    if [ -w "$FABKIT_ROOT" ]; then
        # tar -C "$FABKIT_ROOT" -xzvf "${FABKIT_TARBALL}"
        # rm ${FABKIT_TARBALL}
        ( (echo -en "Installing into $(cyan "${FABKIT_ROOT}")" && git clone git@bitbucket.org:everledger/fabkit "$FABKIT_ROOT" &>/dev/null) || __error "Error cloning remote repository") &
        __spinner
        echo
    else
        yellow "!!!!! ATTENTION !!!!!"
        yellow "Directory \"${FABKIT_ROOT}\" requires superuser permissions"
        yellow "Be sure you are setting an installation path accessible from your current user (preferably under ${HOME})!"
        exit
    fi
}

__set_installation_type() {
    FABKIT_RUNNER="${FABKIT_ROOT}/fabkit"
    FABKIT_RUNNER_DOCKER='docker run -it --rm --name fabkit -e "FABKIT_HOST_ROOT=$FABKIT_ROOT" -v /var/run/docker.sock:/var/run/docker.sock -v "$FABKIT_ROOT":/home/fabkit everledgerio/fabkit:FABKIT_VERSION ./fabkit "$@"'
    FABKIT_RUNNER_DOCKER=${FABKIT_RUNNER_DOCKER/FABKIT_VERSION/$FABKIT_VERSION}

    OS="$(uname)"
    case $OS in
    Linux | FreeBSD | Darwin)
        blue "Great! It looks like your system supports Fabric natively, but you can also run it a docker container."
        echo
        blue "Choose any of these options: "
        echo
        cyan "1) Local installation (recommended)"
        cyan "2) Docker installation"

        read -r n
        case $n in
        1)
            FABKIT_CMD="${FABKIT_RUNNER}"
            green "Roger. Initiating local install!"
            ;;
        2)
            FABKIT_CMD="'${FABKIT_RUNNER_DOCKER}'"
            green "Roger. Initiating docker install!"
            __install_docker &
            __spinner
            ;;
        esac
        ;;
    *)
        yellow "It looks like your system does NOT support natively Fabric, but don't worry, we've got you covered!"
        FABKIT_CMD="${FABKIT_RUNNER_DOCKER}"
        ;;
    esac
}

__install_docker() {
    FABKIT_DOCKER_IMAGE+=":latest"
    echo -en "Downloading the official Fabkit docker image $(cyan ${FABKIT_DOCKER_IMAGE})..."
    docker pull "${FABKIT_DOCKER_IMAGE}" &>/dev/null || __error "Error pulling ${FABKIT_DOCKER_IMAGE}"
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

if git remote -v 2>/dev/null | grep "fabkit" &>/dev/null; then
    cyan "Looks like you want to run Fabkit from inside its repository path"
    git fetch origin --tags &>/dev/null || __error "Error fetching tags from origin"
    FABKIT_VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)
    FABKIT_VERSION=${FABKIT_VERSION:-latest}
    echo
    cyan "Pulling ${FABKIT_VERSION} version"
    cyan "Going to set - ${PWD} - as your installation path!"
    echo
    FABKIT_ROOT="$PWD"
else
    __download_and_extract
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
echo "For more information visit:" "$(cyan "https://bitbucket.org/everledger/fabkit/src/master/docs/")"
echo
echo
green "Have fun! 💃🕺"
