{ system, pkgs, ... }: {


  #
  # sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d "*.house.flakm.com" --preferred-challenges dns-01
  #
  #environment.systemPackages = with pkgs; [
  #  certbot-full
  #];

  services.certbot = {
    enable = true;
    agreeTerms = true;
    package = pkgs.certbot.withPlugins (ps: with ps; [ python311Packages.certbot-dns-cloudflare ]);
  };


}
