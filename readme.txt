# Instructions for PLDI'16 Artifact Evaluation
<br>

This document contains the instructions for compiling and running the system described in our PLDI submission: a certified operating system kernel guarantees security. We intend to clarify in this document every detail the AEC members may need to consider. If you have any question, please do not hesitate to send an email to:
- David Costanzo (david.costanzo@yale.edu )
- Ronghui Gu (ronghui.gu@yale.edu)

## 1. The structure of the package

We will explain each of the file in the main directory in more detail below.

### 1.1 `certikos`

  The source code of our mCertiKOS. It includes:

Folder    | Description
--------- | ----------------------------------
compcert  | the Compcert compiler
compcertx | the extended Compcert
liblayers | the layer library
mcertikos | the Coq proof of mCertiKOS
kernel    | the project to bootstrap mCertiKOS

### 1.2 `PLDI16AE_Ubuntu15.04_x86_64.ovf`

  Virtual Box image of the environment to build mCertiKOS image.

## 2. Preparation for the environment
Inside the Virtual Box image `PLDI16AE_Ubuntu15.04_x86_64.ovf`, we have installed the Ubuntu 15.04, and downloaded the full source code of mCertiKOS (in `/home/certikos/workspace/certikos`) together with the extracted verified assembly code (in `/home/certikos/workspace/certikos/kernel/sys/kern/certikos.S`). Although, building the whole proof and extraction can be fully done within the virtual guest machine, it will take a **large** amount of time to complete. Thus, we **strongly** recommend build the proof directly on a Linux workstation. To give you a rough idea, it takes about 5 hours to compile the full proof and extract the certified assembly code on an 8 core (with hyperthreading) machine with 32 GB of memory, with maximum of 16 parallel threads (`make -j16`).

To compile and extract mCertiKOS, the following tools are needed:
- Operating System: Linux (Ubuntu 15.04 is recommended).
- `Coq`: version 8.4pl4. (Coq 8.5 is not supported because of the CompCert).
- `OCaml`: version 4 (used for code extraction)

To compile the kernel with extracted mCertiKOS assembly and to build the mCertiKOS kernel image, the following tools are needed:
- `gcc`: (32 bit version)
- `libc6`: (32 bit version)
- `build-essential`: (for 'make' system)

mCertiKOS is used in a special testbed platform, which requires certain hardware. As a result, it can not run on top of arbitrary computer. There are two ways to test the built mCertiKOS image:
- A bare-metal machine satisfying the following specification:
  - ITX Motherboard Chassis System (1407664/2809001)
  - 120 Watt AC/DC Adapter 120 Watt DC-DC ATX Pico Power Supply
  - Intel&#174; Desktop Board DQ67EP / DQ77KB
  - Intel Quad Core i7-2600S 2.8GHz (Max Turbo Frequency 3.8GHz) CPU
  - 8GB DDR3 Memory Modules
  - Bootable Compact Flash Converter
  - PCI-Express Mini Card, 120GB 2.5" MLC SSD
  - 9" 9-Pin to 10-Pin Adapter with Applicable Cables
  - A USB stick with 32.0+ GB space

- An easier way is to use 'qemu'.

We recommend start the checking process in the following three steps:
- Install the necessary software to compile and extract mCertiKOS assembly on either a local Linux workstation or on a Linux Cloud machine. And follow necessary instructions in the next sections to make sure all the proof compiles and the code extraction works.
- Start the Virtualbox image `PLDI16AE_Ubuntu15.04_x86_64.ovf` with relatively newer version of Virtualbox. In the guest Linux, we have installed all the tools above. The password of the internal Linux is a single letter "a". Compare and verify that the extracted code is indeed identical to the one in  `/home/certikos/workspace/certikos/kernel/sys/kern/certikos.S`. If you are unsure about it, you can set up necessary shared folder with Virtualbox to copy your newly extracted code to the guest, overwritting the old one. Build mCertiKOS and test whether the small test program we have prepared for you works as expected.

In case you want to build everything locally, we will explain how you can install all the necessary tools on a clean amd64 version of Ubuntu 15.04 (which can be downloaded from [here](http://releases.ubuntu.com/15.04/ubuntu-15.04-desktop-amd64.iso)).
- install all the essential tools by:

  ```bash
  sudo apt-get install gcc-multilib libc6-i386 build-essential \
  m4 ocaml camlp4-extra qemu-utils qemu-system-x86 git netcat menhir
  ```

- download and install coq

  ```bash
  # download Coq
  wget https://coq.inria.fr/distrib/V8.4pl4/files/coq-8.4pl4.tar.gz
  tar -vxzf coq-8.4pl4.tar.gz
  rm coq-8.4pl4.tar.gz

  # compile and install Coq
  cd coq-8.4pl4
  ./configure
  make
  sudo make install
  ```
