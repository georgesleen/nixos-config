# Right Shift activates a left-hand numeric keypad on every keyboard.
# Left Shift preserves the shifted number-row symbols.

{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main.rightshift = "layer(numeric_keypad)";
        numeric_keypad = {
          c = "2";
          d = "5";
          e = "8";
          f = "6";
          r = "9";
          s = "4";
          space = "0";
          v = "3";
          w = "7";
          x = "1";
        };
      };
    };
  };
}
