//===- test.cpp -------------------------------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Copyright (C) 2024, Advanced Micro Devices, Inc.
//
//===----------------------------------------------------------------------===//

#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "cxxopts.hpp"
#include "test_utils.h"
#include "xrt/xrt_bo.h"
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"



#include <iostream>
#include <fstream>
#include <unistd.h>
#include <cstdint>
#include <string>

#define _XOPEN_SOURCE 700
#include <fcntl.h> /* open */
#include <stdint.h> /* uint64_t  */
#include <stdio.h> /* printf */
#include <stdlib.h> /* size_t */
#include <unistd.h> /* pread, sysconf */

typedef struct {
    uint64_t pfn : 55;
    unsigned int soft_dirty : 1;
    unsigned int file_page : 1;
    unsigned int swapped : 1;
    unsigned int present : 1;
} PagemapEntry;

/* Parse the pagemap entry for the given virtual address.
 *
 * @param[out] entry      the parsed entry
 * @param[in]  pagemap_fd file descriptor to an open /proc/pid/pagemap file
 * @param[in]  vaddr      virtual address to get entry for
 * @return 0 for success, 1 for failure
 */
int pagemap_get_entry(PagemapEntry *entry, int pagemap_fd, uintptr_t vaddr)
{
    size_t nread;
    ssize_t ret;
    uint64_t data;
    uintptr_t vpn;

    vpn = vaddr / sysconf(_SC_PAGE_SIZE);
    nread = 0;
    while (nread < sizeof(data)) {
        ret = pread(pagemap_fd, ((uint8_t*)&data) + nread, sizeof(data) - nread,
                vpn * sizeof(data) + nread);
        nread += ret;
        if (ret <= 0) {
            return 1;
        }
    }
    entry->pfn = data & (((uint64_t)1 << 55) - 1);
    entry->soft_dirty = (data >> 55) & 1;
    entry->file_page = (data >> 61) & 1;
    entry->swapped = (data >> 62) & 1;
    entry->present = (data >> 63) & 1;
    return 0;
}

/* Convert the given virtual address to physical using /proc/PID/pagemap.
 *
 * @param[out] paddr physical address
 * @param[in]  pid   process to convert for
 * @param[in] vaddr virtual address to get entry for
 * @return 0 for success, 1 for failure
 */
int virt_to_phys_user(uintptr_t *paddr, pid_t pid, uintptr_t vaddr)
{
    char pagemap_file[BUFSIZ];
    int pagemap_fd;

    snprintf(pagemap_file, sizeof(pagemap_file), "/proc/%ju/pagemap", (uintmax_t)pid);
    pagemap_fd = open(pagemap_file, O_RDONLY);
    if (pagemap_fd < 0) {
        return 1;
    }
    PagemapEntry entry;
    if (pagemap_get_entry(&entry, pagemap_fd, vaddr)) {
        return 1;
    }
    close(pagemap_fd);
    *paddr = (entry.pfn * sysconf(_SC_PAGE_SIZE)) + (vaddr % sysconf(_SC_PAGE_SIZE));
    return 0;
}


constexpr int OUT_SIZE = 64;
std::string formatBinary8(uint32_t val) {
  std::bitset<32> bits(val);
  std::string str = bits.to_string();
  // Insert spaces every 8 bits
  return str.substr(0, 8) + " " + str.substr(8, 8) + " " + str.substr(16, 8) + " " + str.substr(24, 8);
}

int main(int argc, const char *argv[]) {
  // Program arguments parsing
  cxxopts::Options options("add_one_ctrl_packet");
  test_utils::add_default_options(options);

  cxxopts::ParseResult vm;
  test_utils::parse_options(argc, argv, options, vm);

  std::vector<uint32_t> instr_v =
      test_utils::load_instr_binary(vm["instr"].as<std::string>());

  int verbosity = vm["verbosity"].as<int>();
  if (verbosity >= 1)
    std::cout << "Sequence instr count: " << instr_v.size() << "\n";

  // Start the XRT test code
  // Get a device handle
  unsigned int device_index = 0;
  auto device = xrt::device(device_index);

  // Load the xclbin
  if (verbosity >= 1)
    std::cout << "Loading xclbin: " << vm["xclbin"].as<std::string>() << "\n";
  auto xclbin = xrt::xclbin(vm["xclbin"].as<std::string>());

  if (verbosity >= 1)
    std::cout << "Kernel opcode: " << vm["kernel"].as<std::string>() << "\n";
  std::string Node = vm["kernel"].as<std::string>();

  // Get the kernel from the xclbin
  auto xkernels = xclbin.get_kernels();
  auto xkernel = *std::find_if(xkernels.begin(), xkernels.end(),
                               [Node](xrt::xclbin::kernel &k) {
                                 auto name = k.get_name();
                                 std::cout << "Name: " << name << std::endl;
                                 return name.rfind(Node, 0) == 0;
                               });
  auto kernelName = xkernel.get_name();

  if (verbosity >= 1)
    std::cout << "Registering xclbin: " << vm["xclbin"].as<std::string>()
              << "\n";

  device.register_xclbin(xclbin);

  // get a hardware context
  if (verbosity >= 1)
    std::cout << "Getting hardware context.\n";
  xrt::hw_context context(device, xclbin.get_uuid());

  // get a kernel handle
  if (verbosity >= 1)
    std::cout << "Getting handle to kernel:" << kernelName << "\n";
  auto kernel = xrt::kernel(context, kernelName);

  auto bo_instr = xrt::bo(device, instr_v.size() * sizeof(int),
                          XCL_BO_FLAGS_CACHEABLE, kernel.group_id(1));
  auto bo_ctrlOut = xrt::bo(device, OUT_SIZE * sizeof(int32_t),
                            XRT_BO_FLAGS_HOST_ONLY, kernel.group_id(3));

  // void *host_ptr;
  // posix_memalign(&host_ptr,4096,OUT_SIZE*sizeof(int32_t));

  // auto bo_ctrlIn = xrt::bo (device, (int32_t*)host_ptr, OUT_SIZE*sizeof(int32_t), 
  //                       XRT_BO_FLAGS_HOST_ONLY ,kernel.group_id(4));
  auto bo_ctrlIn = xrt::bo(device, OUT_SIZE * sizeof(int32_t),
                        XRT_BO_FLAGS_HOST_ONLY, kernel.group_id(4));

  auto bo_out = xrt::bo(device, OUT_SIZE * sizeof(int32_t),
                        XRT_BO_FLAGS_HOST_ONLY, kernel.group_id(5));

  if (verbosity >= 1)
    std::cout << "Writing data into buffer objects.\n";

  uint32_t beats = 1 - 1;
  uint32_t operation = 0;
  uint32_t stream_id = 0;
  auto parity = [](uint32_t n) {
    uint32_t p = 0;
    while (n) {
      p += n & 1;
      n >>= 1;
    }
    return (p % 2) == 0;
  };

  // Lock0_value
  uint32_t address = 0x0001F000;
  uint32_t header0 = stream_id << 24 | operation << 22 | beats << 20 | address;
  header0 |= (0x1 & parity(header0)) << 31;

  // Lock2_value
  address += 0x20;
  uint32_t header1 = stream_id << 24 | operation << 22 | beats << 20 | address;
  header1 |= (0x1 & parity(header1)) << 31;

  // set lock values to 2
  uint32_t data = 2;
  std::vector<uint32_t> ctrlPackets = {
      header0,
      data,
      header1,
      data,
  };
  // Read 8 32-bit values from "other_buffer" at address 0x440 using two
  // control packets
  for (int i = 0; i < 2; i++) {
    address = 0x440 + i * sizeof(uint32_t) * 4; // 4 because maximum of 4 words in response???
    operation = 0x1;
    stream_id = 0x2;  //path for read response to be back
    beats = 3;  //4-1 == 3?
    uint32_t header2 =
        stream_id << 24 | operation << 22 | beats << 20 | address;
    header2 |= (0x1 & parity(header2)) << 31;
    ctrlPackets.push_back(header2);
  }
  for (size_t i = 0; i < ctrlPackets.size(); ++i) {
    std::cout << "ctrlPackets[" << i << "] = "
              << formatBinary8(ctrlPackets[i]) << std::endl;
  }
  void *bufctrlIn = bo_ctrlIn.map<void *>();


  memcpy(bufctrlIn, ctrlPackets.data(), ctrlPackets.size() * sizeof(int));

  void *bufInstr = bo_instr.map<void *>();
  memcpy(bufInstr, instr_v.data(), instr_v.size() * sizeof(int));

  bo_instr.sync(XCL_BO_SYNC_BO_TO_DEVICE);
  bo_ctrlIn.sync(XCL_BO_SYNC_BO_TO_DEVICE);

  if (verbosity >= 1)
    std::cout << "Running Kernel.\n";
  unsigned int opcode = 3;
  auto run =
      kernel(opcode, bo_instr, instr_v.size(), bo_ctrlOut, bo_ctrlIn, bo_out);

  ert_cmd_state r = run.wait();
  if (r != ERT_CMD_STATE_COMPLETED) {
    std::cout << "Kernel did not complete. Returned status: " << r << "\n";
    return 1;
  }

  bo_out.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
  bo_ctrlOut.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

  uint32_t *bufOut = bo_out.map<uint32_t *>();
  uint32_t *ctrlOut = bo_ctrlOut.map<uint32_t *>();

  int errors = 0;

  for (uint32_t i = 0; i < 8; i++) {
    uint32_t ref = 7 + i;
    if (*(bufOut + i) != ref) {
      std::cout << "Error in dma output " << *(bufOut + i) << " != " << ref
                << std::endl;
      errors++;
    } else {
      std::cout << "Correct dma output " << *(bufOut + i) << " == " << ref
                << std::endl;
    }
  }

  for (uint32_t i = 0; i < 8; i++) {
    uint32_t ref = 8 + i;
    if (*(ctrlOut + i) != ref) {
      std::cout << "Error in control output " << *(ctrlOut + i) << " != " << ref
                << std::endl;
      errors++;
    } else {
      std::cout << "Correct control output " << *(ctrlOut + i) << " == " << ref
                << std::endl;
    }
  }

  // auto ctrlInPtr = bo_ctrlIn.map<int32_t*>();  // Map buffer to host memory
  // for (size_t i = 0; i < OUT_SIZE; ++i) {
  //     std::cout << "ctrlIn[" << i << "] = 0x"
  //               << std::setw(8) << std::setfill('0') << std::hex << ctrlInPtr[i]
  //               << std::endl;
  // }
  auto pid = (uintmax_t)getpid();
  std::cout << "PID is " << pid << std::endl;
  uintptr_t paddr_bufctrlIn = 0;
  uintptr_t vaddr_bufctrlIn = reinterpret_cast<uintptr_t>(bufctrlIn);
  if(virt_to_phys_user(&paddr_bufctrlIn, pid, vaddr_bufctrlIn)){
    std::cerr << "failed to translate virtual to physical"<< std::endl;
  }


  std::cout << "Virtual address bufctrlIn: " << std::hex << vaddr_bufctrlIn << std::endl;
  std::cout << "Physical address bufctrlIn: " << std::hex << paddr_bufctrlIn << std::endl;





  if (!errors) {
    std::cout << "\nPASS!\n\n";
    return 0;
  } else {
    std::cout << "\nfailed.\n\n";
    return 1;
  }
}