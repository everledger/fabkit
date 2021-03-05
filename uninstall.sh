#!/usr/bin/env bash

ALIASES=("fabkit" "fk")

__clear_setup() {
    local shell="$1"
    local profile="${HOME}/.${shell}rc"

    if [ "$shell" = "fish" ]; then
        profile="${HOME}/.config/fish/config.fish"
    fi

    # Remove fabkit root
    if [[ $(grep "^export FABKIT_ROOT=" "$profile") ]]; then
        grep -v "export FABKIT_ROOT=" ${profile} >.${shell}.bk
        mv .${shell}.bk ${profile}
    fi

    # Remove comments
    if [[ $(grep "^# Fabkit" "$profile") ]]; then
        grep -v "# Fabkit" ${profile} >.${shell}.bk
        mv .${shell}.bk ${profile}
    fi

    # Remove aliases
    for alias in "${ALIASES[@]}"; do
        if grep -q "alias ${alias}" <"$profile"; then
            grep -v "alias ${alias}" ${profile} >.${shell}.bk
            mv .${shell}.bk ${profile}
        fi
    done
}

__remove_docker_images() {
    docker rmi $(docker images --filter=reference='everledgerio/fabkit' -q) -f &>/dev/null || return 0
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
blue "Welcome to the Fabkit's uninstaller 🧰 "
blue "We are sad to see you go! :("
echo
read -n 1 -s -r -p "Press any key to start! (or CTRL-C to exit) "
echo
echo
(
    echo -ne "Uninstalling..."
    case $SHELL in
    *bash)
        __clear_setup bash
        ;;
    *zsh)
        __clear_setup zsh
        ;;
    *fish)
        __clear_setup fish
        ;;
    esac
    __remove_docker_images
) &
__spinner
echo
yellow "For security reasons we haven't deleted the Fabkit folder :)"
echo
green "Thank you for using Fabkit! 🚀"
