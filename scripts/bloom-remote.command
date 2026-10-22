#!/bin/zsh
# Double-click to open the Bloom Remote control panel in your browser.
cd "${0:A:h}"
exec /usr/bin/env python3 bloom-remote-gui.py
