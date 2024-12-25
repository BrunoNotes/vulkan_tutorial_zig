!#/bin/bash

sudo dnf install wayland-devel libxkbcommon-devel libXcursor-devel libXi-devel libXinerama-devel libXrandr-devel

cd $PWD/third_party/glfw
cmake -S . -B build

cd $PWD/third_party/glfw/build
make
