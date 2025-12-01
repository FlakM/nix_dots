{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:

{
  boot.extraModulePackages = with pkgs; [
    config.boot.kernelPackages.turbostat
  ];

  boot.kernelModules = [ "msr" ];

  environment.systemPackages = with pkgs; [
    # turbostat - use matching kernel version
    config.boot.kernelPackages.turbostat
    perf

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
