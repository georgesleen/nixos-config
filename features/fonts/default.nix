# Font configuration shared across hosts

# Font configuration shared across hosts
{ pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      inter
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      jetbrains-mono
      pkgs.nerd-fonts."jetbrains-mono"

      (pkgs.runCommand "track-font" { } ''
        mkdir -p $out/share/fonts/opentype
        # Adjust the relative path below (`../assets/fonts/track`) 
        # depending on where fonts.nix is relative to your assets folder.
        cp -r ${../../assets/fonts/track}/*.otf $out/share/fonts/opentype/
      '')
    ];

    fontconfig = {
      defaultFonts = {
        sansSerif = [
          "Inter"
          "Noto Sans"
        ];
        serif = [ "Noto Serif" ];
        monospace = [
          "JetBrainsMono Nerd Font"
          "JetBrains Mono"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
