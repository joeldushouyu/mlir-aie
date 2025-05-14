//===- aie.mlir ------------------------------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// (c) Copyright 2024 Advanced Micro Devices, Inc.
//
//===----------------------------------------------------------------------===//
// examples from  https://github.com/Xilinx/mlir-aie/tree/main/test/npu-xrt/add_one_ctrl_packet
module {
  aie.device(npu2) {
    memref.global "public" @out0 : memref<8xi32>
    memref.global "public" @ctrl0 : memref<8xi32>
    memref.global "public" @ctrlin0 : memref<8xi32>


    %tile_0_0 = aie.tile(0, 0) {controller_id = #aie.packet_info<pkt_type = 0, pkt_id = 4>}
    %tile_0_2 = aie.tile(0, 2) {allocation_scheme = "basic-sequential"}

    %input_lock0 = aie.lock(%tile_0_2, 0) {init = 0 : i32, sym_name = "input_lock0"}
    %input_lock2 = aie.lock(%tile_0_2, 2) {init = 0 : i32, sym_name = "input_lock2"}
    %output_lock4 = aie.lock(%tile_0_2, 4) {init = 0 : i32, sym_name = "output_lock4"}
    %output_lock5 = aie.lock(%tile_0_2, 5) {init = 1 : i32, sym_name = "output_lock5"}

    %debug_out_prod = aie.lock(%tile_0_2, 6) {init = 0: i32, sym_name = "debug_out_prod"}
    %debug_out_con = aie.lock(%tile_0_2, 7) {init = 0: i32, sym_name = "debug_out_con"}
    %debug_out_buf = aie.buffer(%tile_0_2){sym_name = "debug_out_buf"} : memref<4xi32>

    %debug_in_prod = aie.lock(%tile_0_2, 8) {init = 1: i32, sym_name = "debug_in_prod"}
    %debug_in_con = aie.lock(%tile_0_2, 9) {init = 0: i32, sym_name = "debug_in_con"}
    %debug_in_buf = aie.buffer(%tile_0_2){sym_name = "debug_in_buf"} : memref<1xi32>


    %input_buffer = aie.buffer(%tile_0_2) {sym_name = "input_buffer"} : memref<8xi32>
    %output_buffer = aie.buffer(%tile_0_2) {sym_name = "output_buffer"} : memref<8xi32>
    %other_buffer = aie.buffer(%tile_0_2) {address=0x440 : i32,  sym_name = "other_buffer"} : memref<8xi32>

    aie.packet_flow(0x1) {
      aie.packet_source<%tile_0_0, DMA : 0>
      aie.packet_dest<%tile_0_2, TileControl : 0>
    }
    aie.packet_flow(0x2) {
      aie.packet_source<%tile_0_2, TileControl : 0>
      aie.packet_dest<%tile_0_0, DMA : 0>
    }
    aie.packet_flow(0x3) {
      aie.packet_source<%tile_0_2, DMA : 0>
      aie.packet_dest<%tile_0_0, DMA : 1>
    }


    // TODO maybe more fancy later through the FIFO port on it?
    aie.packet_flow(0x4) {
      aie.packet_source<%tile_0_2, DMA : 1>
      aie.packet_dest<%tile_0_0, TileControl : 0>
    }

    // TODO maybe more fancy later through the FIFO port on it?
    aie.packet_flow(0x6) {
      aie.packet_source<%tile_0_0, TileControl : 0>
      aie.packet_dest<%tile_0_2, DMA : 1>
    }



    // aie.flow(%tile_0_0, DMA : 1, %tile_0_2, DMA : 1)

    %core_0_2 = aie.core(%tile_0_2) {
      %c0 = arith.constant 0 : index
      %c1_i32 = arith.constant 1 : i32
      %c3_i32 = arith.constant 3 : i32
      %c1 = arith.constant 1 : index
      %c8 = arith.constant 8 : index
      %c2 = arith.constant 2 : index      
      %c3 = arith.constant 3 : index        
      %c4 = arith.constant 4 : index
      %control_read_bd_0_1_ret_1 = arith.constant 0x8641d004 : i32
      %control_write_MM2S_queue = arith.constant 0x8401d214 : i32
      %control_write_bd_0_1 = arith.constant 0x8401d004 : i32 
      %c80000000 = arith.constant 0x80000000: i32
      %c77fbb008 = arith.constant 0x77fbb008: i32
      // initialize to i + 3
      scf.for %arg1 = %c0 to %c8 step %c1 {
        %arg1_i32 = arith.index_cast %arg1 : index to i32
        %1 = arith.addi %arg1_i32, %c3_i32 : i32
        memref.store %1, %input_buffer[%arg1] : memref<8xi32> // store input_buffer[i] =   i+3
        memref.store %c1_i32, %other_buffer[%arg1] : memref<8xi32> // store  other_buffer[i] = 1
      }
      %c4294967295 = arith.constant 4294967295 : index
      scf.for %arg0 = %c0 to %c4294967295 step %c1 {
        aie.use_lock(%input_lock0, AcquireGreaterEqual, 1)
        scf.for %arg1 = %c0 to %c8 step %c1 {
          // 4
          // add 1 to all input_buffer - > 4,5,6,7,8,9,10...
          %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
          %2 = arith.addi %1, %c1_i32 : i32
          memref.store %2, %input_buffer[%arg1] : memref<8xi32>
        }
        aie.use_lock(%input_lock0, AcquireGreaterEqual, 1)
        scf.for %arg1 = %c0 to %c8 step %c1 {
          // 5
          // add 1 to all input_buffer -> 5,6,7,.....
          %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
          %2 = arith.addi %1, %c1_i32 : i32
          memref.store %2, %input_buffer[%arg1] : memref<8xi32>
        }


        //packet control instruction to write to dma
        // memref.store %control_read_bd_0_1_ret_1, %debug_out_buf[%c0] : memref<2xi32>


      memref.store %control_write_bd_0_1, %debug_out_buf[%c0] : memref<4xi32>
      memref.store %c77fbb008, %debug_out_buf[%c1] : memref<4xi32>
      aie.use_lock(%debug_out_con, Release, 1)
      aie.use_lock(%debug_out_prod, AcquireGreaterEqual, 1) // need to separate into two write
      memref.store %control_write_MM2S_queue, %debug_out_buf[%c0] : memref<4xi32>  //TODO: need twice, cannot merge into one?
      memref.store %c80000000, %debug_out_buf[%c1] : memref<4xi32>
        aie.use_lock(%debug_out_con, Release, 1)
        // // waiting DMA transmission
        // aie.use_lock(%debug_in_con, AcquireGreaterEqual, 1)


        aie.use_lock(%input_lock2, AcquireGreaterEqual, 1)
        scf.for %arg1 = %c0 to %c8 step %c1 {
          // 6
          // add 1 to all input buffer - > 6,7,.....
          %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
          %2 = arith.addi %1, %c1_i32 : i32
          memref.store %2, %input_buffer[%arg1] : memref<8xi32>
        }
        aie.use_lock(%input_lock2, AcquireGreaterEqual, 1)
        scf.for %arg1 = %c0 to %c8 step %c1 {
          // 7
          // add 1 to all input_buffer - > 7,8,9...
          %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
          %2 = arith.addi %1, %c1_i32 : i32
          memref.store %2, %input_buffer[%arg1] : memref<8xi32>
        }
        // write to output buffer
        aie.use_lock(%output_lock5, AcquireGreaterEqual, 1)
        // scf.for %arg1 = %c0 to %c8 step %c1 {
        //     %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
        //     memref.store %1, %output_buffer[%arg1] : memref<8xi32>  //output_buffer[i] = input_buffer[i]
        //     %2 = arith.addi %1, %c1_i32 : i32
        //     memref.store %2, %other_buffer[%arg1] : memref<8xi32> // other_buffer[i] += 1
        // }


        scf.for %arg1 = %c0 to %c8 step %c1 {
            %1 = memref.load %input_buffer[%arg1] : memref<8xi32>
            memref.store %1, %output_buffer[%arg1] : memref<8xi32>  //output_buffer[i] = input_buffer[i]
            %2 = arith.addi %1, %c1_i32 : i32
            memref.store %2, %other_buffer[%arg1] : memref<8xi32> // other_buffer[i] += 1
        }                
        aie.use_lock(%output_lock4, Release, 1)
      }
      aie.end
    }

    %mem_0_2 = aie.mem(%tile_0_2) {
      %0 = aie.dma_start(MM2S, 0, ^bb1, ^bb2)
    ^bb1:  // 2 preds: ^bb0, ^bb2
      aie.use_lock(%output_lock4, AcquireGreaterEqual, 1)
      aie.dma_bd(%output_buffer : memref<8xi32>, 0, 8) {packet = #aie.packet_info<pkt_id = 3, pkt_type = 0>}
      aie.use_lock(%output_lock5, Release, 1)
      aie.next_bd ^bb1
    ^bb2:
      %1 = aie.dma_start(MM2S, 1, ^bb3, ^bb4)
    ^bb3:
      aie.use_lock(%debug_out_con, AcquireGreaterEqual, 1) //TODO: maybe not event need aie.packet_info?
      aie.dma_bd(%debug_out_buf : memref<4xi32>, 0, 2) {packet = #aie.packet_info<pkt_id = 4, pkt_type = 0>}
      aie.use_lock(%debug_out_prod, Release, 1)
      aie.next_bd ^bb3      
    ^bb4:
      %2 = aie.dma_start(S2MM, 1, ^bb5, ^bb6)
    ^bb5:
      aie.use_lock(%debug_in_prod, AcquireGreaterEqual, 1)
      aie.dma_bd(%debug_in_buf : memref<1xi32>, 0, 1)
      aie.use_lock(%debug_in_con, Release, 1)
      aie.next_bd ^bb5
    ^bb6:
      aie.end
    }

    aie.shim_dma_allocation @ctrlin0(MM2S, 0, 0)
    aie.shim_dma_allocation @ctrl0(S2MM, 0, 0)
    aie.shim_dma_allocation @out0(S2MM, 1, 0)

    memref.global "private" constant @blockwrite_data_0 : memref<8xi32> = dense<[2, 0, 0x40090000, 0, 0x40000000, 0, 0, 0x2000000]>
    aiex.runtime_sequence @seq(%arg0: memref<8xi32>, %arg1: memref<16xi32>, %arg2: memref<8xi32>) {
      %c0_i64 = arith.constant 0 : i64
      %c1_i64 = arith.constant 1 : i64
      %c2_i64 = arith.constant 2 : i64
      %c8_i64 = arith.constant 8 : i64
      %c4_i64 = arith.constant 4 : i64
      // set Ctrl_Pkt_Tlast_Error_Enable=0 in Module_Clock_Control register
      // aiex.npu.maskwrite32 {address = 0x00060000 : ui32, column = 0 : i32, row = 2 : i32, value = 0 : ui32, mask = 0x8 : ui32}

      // start reading output
      aiex.npu.dma_memcpy_nd(%arg0[%c0_i64, %c0_i64, %c0_i64, %c0_i64] [%c1_i64, %c1_i64, %c1_i64, %c8_i64] [%c0_i64, %c0_i64, %c0_i64, %c1_i64]) {id = 1 : i64, issue_token = true, metadata = @ctrl0} : memref<8xi32>
      aiex.npu.dma_memcpy_nd(%arg2[%c0_i64, %c0_i64, %c0_i64, %c0_i64] [%c1_i64, %c1_i64, %c1_i64, %c8_i64] [%c0_i64, %c0_i64, %c0_i64, %c1_i64]) {id = 2 : i64, issue_token = true, metadata = @out0} : memref<8xi32>

      // write bd0
      %0 = memref.get_global @blockwrite_data_0 : memref<8xi32>
      // write from 0x1d00 to 0x1D01C  on shimtile?
      // same operation as allocating buffer???
      //0x2 for DMABD_0-> range of [0: 2*4-1] = [0:7]
      //0x0  0 base address offset (for now, this base_address seem refer to the host buffer addres in unified memory)
      //0x40090000 Enable packet and MM2S of packet_ID= 1, packet_tyype=1, with 0x0 base address offset?
      // 0 for D0_warp and D_0Step_size=0 offset
      // 0x40000000 burst_length: 128B D1_warp = 0, D1_stepSize= 0 offset
      // 0: D2_stepSize= 0 offset
      // 0: iteration warp - 0, iteration_stepsize = 0 offset
      // 0x2000000: valid BD = true



      aiex.npu.blockwrite(%0) {address = 0x1d000 : ui32, column = 0 : i32, row = 0 : i32} : memref<8xi32> // patch size of 8*int32
      // // write bd0
      // patch bd0 address for packet 0, push to mm2s_0_task_queue, wait
      //# aiex.npu.address_patch writes the pointer to argument 0 (input, arg_idx=0) to the respective BD0, BD1, ... address plus an offset
      //# 0x1D004  DMA_BD0_1  Base_Address_Low  <- buffer address for bd 0   : FROM https://github.com/Xilinx/mlir-aie/blob/dc4327fd26c8d1c2ab47df3a8f62a1f7a48b934c/test/npu-xrt/sync_task_complete_token_bd_chaining/aie2.py#L111
      // npu_address_patch(
      //     addr=(0x1D004 + j * 0x20), arg_idx=0, arg_plus=buffer_offset
      // )

      // same affect as
      aiex.npu.dma_memcpy_nd(%arg1[%c0_i64, %c0_i64, %c0_i64, %c0_i64] [%c1_i64, %c1_i64, %c1_i64, %c8_i64] [%c0_i64, %c0_i64, %c0_i64, %c1_i64], packet = <pkt_id = 1, pkt_type = 1>) {id = 0: i64, issue_token = true, metadata = @ctrlin0} : memref<16xi32>
      // aiex.npu.address_patch {addr = 0x1d004 : ui32, arg_idx = 1 : i32, arg_plus = 0 : i32}// dma0, use %arg1 with offset of 8 byte? 
      // aiex.npu.maskwrite32 {address = 0x1d210 : ui32, column = 0 : i32, row = 0 : i32, mask = 0x00000F00 : ui32, value = 0x400 : ui32} // set the Task Compltete Token Controller id of DMA_MM2S to be 0x4, same with the control_packed defined when allocating CT_0_0
      // aiex.npu.write32 {address = 0x1d214 : ui32, column = 0 : i32, row = 0 : i32, value = 0x80000000 : ui32}  // This enables token_issue
      //aiex.npu.sync {channel = 0 : i32, column = 0 : i32, column_num = 1 : i32, direction = 1 : i32, row = 0 : i32, row_num = 1 : i32} //This block shimtile operation until a task-completition token is received at colum, row (CT_0_0) for MM2S from its receiver

      //patch bd0 address for packet 1, push to mm2s_0_task_queue, wait
      //aiex.npu.write32 {address = 0x1d004 : ui32, column = 0 : i32, row = 0 : i32, value = 0x77fbb008 : ui32}    // aiex.npu.address_patch {addr = 0x1d004 : ui32, arg_idx = 1 : i32, arg_plus = 8 : i32} // dma0, use %arg1 with offset of 8 byte?
     // aiex.npu.write32 {address = 0x1d214 : ui32, column = 0 : i32, row = 0 : i32, value = 0x80000000 : ui32} // enable token issue
      //aiex.npu.sync {channel = 0 : i32, column = 0 : i32, column_num = 1 : i32, direction = 1 : i32, row = 0 : i32, row_num = 1 : i32} // wait until CT_0_0 receive task-complete-token from receiver
      // or same as below
      //offset of two, 2*4Byte(per int32) = 8 byte offeset 
      //aiex.npu.dma_memcpy_nd(%arg1[%c0_i64, %c0_i64, %c0_i64, %c2_i64] [%c1_i64, %c1_i64, %c1_i64, %c8_i64] [%c0_i64, %c0_i64, %c0_i64, %c1_i64], packet = <pkt_id = 1, pkt_type = 1>) {id = 0: i64, issue_token = true, metadata = @ctrlin0} : memref<16xi32>
      // wait for dma output
      aiex.npu.dma_wait {symbol = @out0} // wait for S2MM, the output

      // patch bd0 length and address for packet 2, push to mm2s_0_task_queue, wait
      aiex.npu.write32 {address = 0x1d000 : ui32, column = 0 : i32, row = 0 : i32, value = 1 : ui32} // change buffer size now to [0:3] 4 byte instead
      aiex.npu.address_patch {addr = 0x1d004 : ui32, arg_idx = 1 : i32, arg_plus = 16 : i32} // argument %arg1, with offset of 16 Byte
      aiex.npu.write32 {address = 0x1d214 : ui32, column = 0 : i32, row = 0 : i32, value = 0x80000000 : ui32}  // enable token issue
      aiex.npu.sync {channel = 0 : i32, column = 0 : i32, column_num = 1 : i32, direction = 1 : i32, row = 0 : i32, row_num = 1 : i32}  // wait until CT_0_0 receive task-complete-token from receiver

      // patch bd0 address for packet 3, push to mm2s_0_task_queue, wait
      aiex.npu.address_patch {addr = 0x1d004 : ui32, arg_idx = 1 : i32, arg_plus = 20 : i32}// argument %arg1, with offset of 20 Byte, 
      aiex.npu.write32 {address = 0x1d214 : ui32, column = 0 : i32, row = 0 : i32, value = 0x80000000 : ui32}
      aiex.npu.sync {channel = 0 : i32, column = 0 : i32, column_num = 1 : i32, direction = 1 : i32, row = 0 : i32, row_num = 1 : i32}

      // wait for control port output
      aiex.npu.dma_wait {symbol = @ctrl0} // wait for S2MM, the output
    }
  }
}