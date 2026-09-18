# cxdb name routing: sso.cx10.db.test:5434 instead of 127.0.0.1:<per-alias port>.
# dnsmasq serves *.db.test from the hostsdir cxdb writes into; systemd-resolved
# sends the domain there over a dummy link, because resolved routes domains per
# link, never per global server (a global DNS=127.0.0.1:5354 would share every
# query with 192.168.0.102 and loop through dnsmasq).
# Add `./cxdb-dns.nix` to the imports in configuration.nix.
{ pkgs, ... }:
let
  domain = "db.test";
  port = 5354; # 53 is resolved's stub, 5353 is mDNS (spotify/avahi)
  hostsdir = "/run/cxdb/hosts";
  user = "flakm";
  addr = "192.0.2.1"; # RFC 5737 TEST-NET-1, never routed
in
{
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # /etc/resolv.conf stays resolved's
    settings = {
      port = port;
      listen-address = "127.0.0.1";
      bind-interfaces = true;
      no-resolv = true; # never forward; only ${domain} lives here
      no-hosts = true;
      local = "/${domain}/";
      hostsdir = hostsdir;
    };
  };

  systemd.tmpfiles.rules = [ "d ${hostsdir} 0755 ${user} users -" ];

  # dhcpcd claims every new link; with no lease its resolvconf hook runs
  # `resolvectl revert cxdb0`, wiping the DNS settings below.
  networking.dhcpcd.denyInterfaces = [ "cxdb0" ];

  systemd.services.cxdb-dns-route = {
    description = "route ${domain} to dnsmasq over a dummy link";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-resolved.service" "dnsmasq.service" ];
    requires = [ "systemd-resolved.service" ];
    partOf = [ "systemd-resolved.service" ]; # resolved forgets per-link state on restart
    path = [ pkgs.iproute2 pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip link show cxdb0 >/dev/null 2>&1 || ip link add cxdb0 type dummy
      ip link set cxdb0 up
      # resolved ignores a link whose only address is link-scope (fe80::), leaving
      # `Current Scopes: none` and the domain unrouted however it is configured.
      ip addr show dev cxdb0 | grep -q ${addr} || ip addr add ${addr}/32 dev cxdb0
      resolvectl dns cxdb0 127.0.0.1:${toString port}
      resolvectl domain cxdb0 "~${domain}"
      resolvectl default-route cxdb0 false
      resolvectl llmnr cxdb0 no
      resolvectl mdns cxdb0 no
    '';
  };
}
