#!/bin/sh

if $HOME/bin/ejabberdctl status>/dev/null 2>/dev/null && [ -e $HOME/.ejabberd_ready ]; then
    return 0
else
    return 3
fi
