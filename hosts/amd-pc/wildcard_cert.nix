{ system, pkgs, ... }: {


  #
  # sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d "*.house.flakm.com" --preferred-challenges dns-01
  #
  environment.systemPackages = with pkgs; [
    certbot-full
  ];


}
