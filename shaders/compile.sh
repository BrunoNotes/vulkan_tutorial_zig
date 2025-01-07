#!/bin/bash

SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`

 # glslc "${SCRIPTPATH}/shader.vert" -o "${SCRIPTPATH}/vert.spv"
 # glslc "${SCRIPTPATH}/shader.frag" -o "${SCRIPTPATH}/frag.spv"
 glslc -fshader-stage="vertex" "${SCRIPTPATH}/vert.glsl" -o "${SCRIPTPATH}/vert.spv"
 glslc -fshader-stage="fragment" "${SCRIPTPATH}/frag.glsl" -o "${SCRIPTPATH}/frag.spv"
