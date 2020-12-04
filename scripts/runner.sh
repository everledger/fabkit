#!/usr/bin/env bash

case $SHELL in
*bash)
    if [[ ! $(cat ~/.bashrc | grep fabkit) ]]; then
        echo "alias fabkit=./fabkit" >>~/.bashrc
        source ~/.bashrc
    fi
    ;;
*zsh)
    if [[ ! $(cat ~/.zshrc | grep fabkit) ]]; then
        echo "alias fabkit=./fabkit" >>~/.zshrc
        source ~/.zshrc
    fi
    ;;
esac
