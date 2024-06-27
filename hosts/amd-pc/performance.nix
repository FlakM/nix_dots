{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:

{
  boot.extraModulePackages = with pkgs; [
    linuxKernel.packages.linux_6_6.turbostat
  ];


  boot.kernelModules = [ "msr" ];

  environment.systemPackages = with pkgs; [
    # turbostat
    linuxKernel.packages.linux_6_6.turbostat
    linuxPackages.perf

    bcc
    bpftrace

    # mpstat
    busybox

    # provides ie pidstat
    sysstat

    # perf
    perf-tools

    # rust port of flamegraph toolkit to Rust
    inferno

    # Brandon Gregg's flamegraph toolkit
    flamegraph
  ];
}
