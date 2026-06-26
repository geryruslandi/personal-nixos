{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    kdePackages.kwallet
    kdePackages.kwalletmanager
  ];

  security.pam.services.sddm.kwallet.enable = true;
  security.pam.services.sddm.kwallet.forceRun = true;

}
