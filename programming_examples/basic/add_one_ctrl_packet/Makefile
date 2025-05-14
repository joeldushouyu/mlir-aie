##===- Makefile -----------------------------------------------------------===##
# 
# This file licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Copyright (C) 2025, Advanced Micro Devices, Inc.
# 
##===----------------------------------------------------------------------===##

srcdir := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

include ${srcdir}/../../makefile-common

XILINX_XRT=/opt/xilinx/xrt/
XILINX_XRT_INCLUDE?=${XILINX_XRT}/include
XILINX_XRT_LIB?=${XILINX_XRT}/lib

XRT_FLAGS=-I${XILINX_XRT_INCLUDE} -L${XILINX_XRT_LIB}
XRT_LIBS=-lxrt_coreutil
CXX=g++-13 -ggdb

UTILS_INCLUDE := -I$(srcdir)/../../../runtime_lib/test_lib/
UTILS_LIB=$(srcdir)/../../../runtime_lib/test_lib/test_utils.cpp

mlir_target?=build/aie.mlir
xclbin_target?=build/aie.xclbin
insts_target?=build/insts.bin
host_target?=build/test

devicename ?= $(if $(filter 1,$(NPU2)),npu2,npu)





.PHONY: all
all: ${xclbin_target} ${host_target}



${mlir_target}: ${srcdir}/aie.mlir 
	mkdir -p ${@D}
	cd ${@D} && cp ${srcdir}/aie.mlir .

${xclbin_target}: ${mlir_target} 
	mkdir -p ${@D}
	cd ${@D} && aiecc.py -v --aie-generate-xclbin --no-compile-host --xclbin-name=${@F} \
				--no-xchesscc --no-xbridge \
				--aie-generate-npu-insts --npu-insts-name=${insts_target:build/%=%} ${<:%=../%}

${host_target}: ${srcdir}/host.cpp ${xclbin_target}
	mkdir -p ${@D}
	${CXX} ${XRT_FLAGS} ${UTILS_INCLUDE} ${UTILS_LIB} -o $@ $< ${XRT_LIBS}

.PHONY: run
run: ${host_target}
	./${host_target} -x build/aie.xclbin -k MLIR_AIE -i build/insts.bin


.PHONY: clean
clean:
	rm -rf build
