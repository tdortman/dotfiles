let
  pubKey = "age1r3ee8yzrvhsqzpur68xpuheg8g66q3g4eu8dk4eft9xyh0nczdhqpn3grr";
in
{
  "airvpn-presharedkey.age".publicKeys = [ pubKey ];
  "airvpn-privatekey.age".publicKeys = [ pubKey ];
  "jgu-vpn-swanctl.age".publicKeys = [ pubKey ];
  "login-password.age".publicKeys = [ pubKey ];
  "nextdns-resolved.conf.age".publicKeys = [ pubKey ];
  "restic-password.age".publicKeys = [ pubKey ];
}
